import copy
import datetime as dt
import io
import json
from pathlib import Path
import re
import sys
import unittest
import tempfile
from contextlib import redirect_stdout
from types import SimpleNamespace
from unittest.mock import patch
import urllib.error
import uuid

sys.path.insert(0, str(Path(__file__).parent))
from controller import Admin, Controller, Failure, NoRedirect, literal, main


def config(env='DEV'):
    return dict(environment=env, project_ref='abcdefghijklmnopqrst',
        project_url='https://abcdefghijklmnopqrst.supabase.co', revision='a'*40,
        actor='synthetic-owner', ticket='M2A-TEST')


def approval(c):
    return {k: v for k, v in dict(c, id=str(uuid.uuid4()), expires_at=(dt.datetime.now(dt.timezone.utc)+dt.timedelta(minutes=10)).isoformat(),
        oracle_retired=True, backlog_authorized=True).items() if k != 'project_url'}


class FakeAdmin:
    def __init__(self, c):
        self.config=c; self.edge_mode='disabled'; self.events=[]; self.probes={}; self.fail=None
        self.state=dict(mode='disabled', environment=c['environment'], project_ref=c['project_ref'], binding_matches=True,
            key_present=True, extensions_ready=True, schedule_count=1, schedule_ready=True, schedule_active=False,
            inflight=0, pending=0, ambiguous=0, last_observe=dt.datetime.now(dt.timezone.utc).isoformat())
        self.routes={k:v['worker_slug'] for k,v in json.loads((Path(__file__).resolve().parents[2]/'services/outbox-dispatcher/routes.json').read_text()).items()}
        self.names={'OUTBOX_NOTIFICATION_KEY','NSE_WORKER_TOKEN'}

    def secret_names(self):return self.names

    def mode(self, mode, config=None):
        self.events.append('edge:'+mode)
        if self.fail=='edge:'+mode: raise Failure('management_unavailable')
        self.edge_mode=mode

    def sql(self, expression):
        if expression.startswith('moneybowl_dispatch.commission('):
            match=re.fullmatch(r"moneybowl_dispatch.commission\('([^']+)',(.*)::jsonb\)", expression)
            action=match[1]; args=json.loads(match[2][1:-1].replace("''", "'"));self.events.append('db:'+action)
            if self.fail=='db:'+action:raise Failure('database_failed')
            if action=='rollback':self.state.update(mode='disabled',schedule_active=False)
            if action=='observe':self.state['mode']='observe'
            if action=='activate':self.state.update(mode='active',schedule_active=True)
            return copy.deepcopy(self.state)
        if expression.startswith('moneybowl_dispatch.commission_probe('):
            match=re.fullmatch(r"moneybowl_dispatch.commission_probe\('([^']+)',(NULL|[0-9]+)\)",expression)
            kind,replay=match.groups();self.events.append('probe:'+kind);idx=len(self.probes)+1
            if kind=='readiness':
                result=dict(status=200,code='outbox_ready',mode=self.edge_mode,environment=self.config['environment'],project_url=self.config['project_url'],routes=self.routes)
            else:result=dict(status=200 if replay=='NULL' else 202,code='outbox_processed' if replay=='NULL' else 'outbox_replay',count=0)
            self.probes[idx]=result;return idx
        match=re.fullmatch(r'moneybowl_dispatch.commission_result\(([0-9]+)\)',expression)
        if match:return self.probes[int(match[1])]
        raise AssertionError('unexpected SQL')


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.c=config();self.a=FakeAdmin(self.c);self.controller=Controller(self.c,self.a,sleep=lambda _:None)

    def test_bootstrap_is_disabled(self):
        for _ in range(2):self.assertEqual(self.controller.run('bootstrap')['mode'],'disabled')
        self.assertNotIn('edge:active',self.a.events)

    def test_qa_and_prod_same_bootstrap_and_observe(self):
        for env in ('QA','PROD'):
            c=config(env);a=FakeAdmin(c);ctl=Controller(c,a)
            self.assertEqual(ctl.run('bootstrap')['mode'],'disabled')
            self.assertEqual(ctl.run('observe')['mode'],'observe')
            with self.assertRaisesRegex(Failure,'activation_dev_only'):ctl.run('activate',approval(c))
            self.assertNotIn('edge:active',a.events)

    def test_config_rejections(self):
        for patch_value in ({'environment':'STAGING'},{'environment':'develop'},{'project_url':'https://wrong.supabase.co'}, {'project_ref':'../secret'}, {'revision':'main'}, {'actor':'owner\nsecret'}, {'ticket':'token\nsecret'}):
            with self.subTest(patch_value=patch_value),self.assertRaises(Failure):Controller(dict(self.c,**patch_value),self.a)

    def test_missing_config(self):
        for key in self.c:
            c=self.c.copy();del c[key]
            with self.subTest(key=key),self.assertRaises(Failure):Controller(c,self.a)

    def test_no_missing_secret_fallback(self):
        for key in ('OUTBOX_NOTIFICATION_KEY','NSE_WORKER_TOKEN'):
            self.a.names={key}
            with self.assertRaisesRegex(Failure,'edge_secret_missing'):self.controller.run('bootstrap')
        self.assertEqual(self.a.events,['db:status','db:status'])

    def test_missing_vault_key(self):
        self.a.state['key_present']=False
        with self.assertRaisesRegex(Failure,'database_not_ready'):self.controller.run('preflight')

    def test_wrong_database_binding(self):
        self.a.state['binding_matches']=False
        with self.assertRaisesRegex(Failure,'database_binding_invalid'):self.controller.run('preflight')

    def test_wrong_edge_binding(self):
        self.a.config=dict(self.c,environment='QA')
        with self.assertRaisesRegex(Failure,'edge_binding_invalid'):self.controller.run('preflight')

    def test_all_seventeen_routes_exact(self):
        self.assertEqual(len(self.controller.routes),17)
        self.a.routes=dict(self.a.routes);self.a.routes.pop(next(iter(self.a.routes)))
        with self.assertRaisesRegex(Failure,'edge_routes_invalid'):self.controller.run('preflight')

    def test_observe_replay_and_no_activation(self):
        self.assertEqual(self.controller.run('observe')['mode'],'observe')
        self.assertEqual(self.a.events.count('probe:recovery'),2)
        self.assertNotIn('db:activate',self.a.events);self.assertNotIn('edge:active',self.a.events)

    def test_active_observe_rejected_before_edge_change(self):
        self.a.state['mode']='active'
        with self.assertRaisesRegex(Failure,'observe_active_conflict'):self.controller.run('observe')
        self.assertNotIn('edge:observe',self.a.events)

    def test_observe_failure_disables_db(self):
        self.a.fail='db:observe'
        with self.assertRaises(Failure):self.controller.run('observe')
        self.assertEqual(self.a.events[-1],'db:rollback');self.assertEqual(self.a.state['mode'],'disabled')

    def test_schedule_does_not_activate(self):
        for _ in range(2):self.assertFalse(self.controller.run('schedule')['schedule_active'])
        self.assertNotIn('edge:active',self.a.events)

    def test_activation_needs_approval(self):
        with self.assertRaisesRegex(Failure,'approval_fields_invalid'):self.controller.run('activate')
        self.assertEqual(self.a.events,[])

    def test_approval_binding(self):
        for key in ('environment','project_ref','revision','actor','ticket'):
            p=approval(self.c);p[key]='wrong'
            with self.assertRaisesRegex(Failure,'approval_binding_invalid'):self.controller.run('activate',p)

    def test_approval_expiry_and_retirement(self):
        for field,value in [('expires_at',(dt.datetime.now(dt.timezone.utc)-dt.timedelta(seconds=1)).isoformat()),('oracle_retired',False),('backlog_authorized',False)]:
            p=approval(self.c);p[field]=value
            with self.assertRaisesRegex(Failure,'approval_invalid'):self.controller.run('activate',p)

    def test_inflight_blocks_activation(self):
        self.a.state['inflight']=1
        with self.assertRaisesRegex(Failure,'activation_inflight_or_active'):self.controller.run('activate',approval(self.c))
        self.assertNotIn('edge:active',self.a.events)

    def test_stale_observe(self):
        self.a.state['last_observe']=(dt.datetime.now(dt.timezone.utc)-dt.timedelta(minutes=20)).isoformat()
        with self.assertRaisesRegex(Failure,'observe_stale'):self.controller.run('eligibility')

    def test_activation_order_and_verification(self):
        result=self.controller.run('activate',approval(self.c))
        self.assertTrue(result['active_configuration_verified']);self.assertFalse(result['business_processing_verified'])
        self.assertLess(self.a.events.index('db:rollback'),self.a.events.index('edge:active'))
        self.assertLess(self.a.events.index('edge:active'),self.a.events.index('db:activate'))

    def test_failed_activation_leaves_disabled_and_recoverable(self):
        for fail in ('edge:active','db:activate'):
            with self.subTest(fail=fail):
                self.setUp();self.a.fail=fail
                with self.assertRaises(Failure):self.controller.run('activate',approval(self.c))
                self.assertEqual(self.a.state['mode'],'disabled');self.assertFalse(self.a.state['schedule_active'])
                self.assertEqual(self.a.edge_mode,'disabled')

    def test_rollback_db_first(self):
        self.a.state.update(mode='active',schedule_active=True);self.a.edge_mode='active'
        result=self.controller.run('rollback')
        self.assertEqual(self.a.events[:2],['db:rollback','edge:disabled'])
        self.assertTrue(result['oracle_restart_safe'])

    def test_rollback_edge_outage_keeps_db_disabled(self):
        self.a.fail='edge:disabled'
        with self.assertRaises(Failure):self.controller.run('rollback')
        self.assertEqual(self.a.state['mode'],'disabled');self.assertFalse(self.a.state['schedule_active'])

    def test_rollback_inflight_not_safe_for_oracle(self):
        self.a.state['inflight']=1
        self.assertFalse(self.controller.run('rollback')['oracle_restart_safe'])

    def test_probe_timeout_is_bounded(self):
        self.a.sql=lambda _: {'pending':True}
        with self.assertRaisesRegex(Failure,'probe_timeout'):self.controller.result(1)

    def test_literal_quotes(self):self.assertEqual(literal("a'b"),"'a''b'")


class TransportTests(unittest.TestCase):
    def test_no_credential(self):
        with self.assertRaisesRegex(Failure,'admin_credential_missing'):Admin('abcdefghijklmnopqrst','')

    def test_redirect_rejected(self):
        with self.assertRaisesRegex(Failure,'management_redirect_rejected'):NoRedirect().redirect_request(None,None,None,None,None,None)

    def test_http_error_does_not_leak_body(self):
        admin=Admin('abcdefghijklmnopqrst','synthetic-private-token')
        with patch.object(admin.opener,'open',side_effect=urllib.error.HTTPError('url',401,'SECRET',{},io.BytesIO(b'SECRET'))):
            with self.assertRaisesRegex(Failure,'^management_http_401$'):admin.secret_names()

    def test_only_fixed_admin_paths(self):
        admin=Admin('abcdefghijklmnopqrst','synthetic-private-token')
        for path in ('https://attacker.invalid','/../secrets','/functions/nse-worker'):
            with self.assertRaisesRegex(Failure,'management_path_invalid'):admin.call(path)


class CommandTests(unittest.TestCase):
    def invoke(self, revision='a'*40, dirty=False, token='', approval_mode=None):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'config.json';path.write_text(json.dumps(config()))
            args=['controller.py','preflight','--config',str(path)]
            if approval_mode is not None:
                p=Path(directory)/'approval.json';p.write_text(json.dumps(approval(config())));p.chmod(approval_mode)
                args=['controller.py','activate','--config',str(path),'--approval',str(p)]
            def git(command,**kwargs):
                return SimpleNamespace(stdout=revision if 'rev-parse' in command else ('dirty' if dirty else ''))
            output=io.StringIO()
            with patch('sys.argv',args), patch('controller.subprocess.run',side_effect=git), patch.dict('os.environ',{'MONEYBOWL_COMMISSION_TOKEN':token}), redirect_stdout(output):
                code=main()
            return code,json.loads(output.getvalue())

    def test_missing_admin_credential_is_sanitized(self):
        self.assertEqual(self.invoke(),(1,{'error':'admin_credential_missing'}))

    def test_dirty_checkout_rejected_without_network(self):
        self.assertEqual(self.invoke(dirty=True,token='SENSITIVE'),(1,{'error':'checkout_dirty'}))

    def test_wrong_revision_rejected_without_network(self):
        self.assertEqual(self.invoke(revision='b'*40,token='SENSITIVE'),(1,{'error':'checkout_revision_mismatch'}))

    def test_world_readable_approval_rejected(self):
        self.assertEqual(self.invoke(approval_mode=0o644),(1,{'error':'approval_permissions_invalid'}))

    def test_complete_cli_preflight_with_mocked_admin(self):
        with patch('controller.Admin',return_value=FakeAdmin(config())):
            code,result=self.invoke(token='SENSITIVE')
        self.assertEqual(code,0);self.assertNotIn('SENSITIVE',json.dumps(result))
        self.assertEqual(result['result']['mode'],'disabled')


if __name__=='__main__':unittest.main()
