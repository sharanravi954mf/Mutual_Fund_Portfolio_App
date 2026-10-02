"""Local deployment simulation. No Docker, Supabase or provider connections."""
import importlib.util
import json
from pathlib import Path
import subprocess
import pytest

BASE = Path(__file__).resolve().parents[1]

def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, BASE / 'deploy' / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

r = module('reconcile', 'reconcile.py')
spool = module('spool', 'process-spool.py')
SHA = 'a' * 40
NEW = 'sha256:' + 'b' * 64
OLD = 'sha256:' + 'c' * 64

def container():
    env = {k: 'synthetic-only' for k in r.SECRETS}
    env.update(dict(zip(r.SETTINGS, ['false','60','30','10','45','30','12'])))
    env.update(OUTBOX_ROUTES_FILE='/app/routes.json', OUTBOX_HEARTBEAT_FILE='/tmp/dispatcher-heartbeat')
    return {'Image': OLD, 'Config': {'User':'10002:10002', 'Env':[k+'='+v for k,v in env.items()],
      'Labels':{'com.docker.compose.project':r.PROJECT,'com.docker.compose.service':r.SERVICE}},
      'HostConfig':{'ReadonlyRootfs':True,'CapDrop':['ALL'],'SecurityOpt':['no-new-privileges:true'],
        'NanoCpus':100000000,'Memory':134217728,'PidsLimit':32,'RestartPolicy':{'Name':'unless-stopped'},
        'Tmpfs':{'/tmp':'size=8m,mode=1777'}},'State':{'Health':{'Status':'healthy'}},
      'NetworkSettings':{'Networks':{r.NETWORK:{}}}}

def config():
    return {'services':{r.SERVICE:{'user':'10002:10002','read_only':True,'cap_drop':['ALL'],
      'security_opt':['no-new-privileges:true'],'cpus':.1,'mem_limit':'134217728','pids_limit':32,
      'restart':'unless-stopped','stop_grace_period':'10s','tmpfs':['/tmp:size=8m,mode=1777'],'networks':{'ingestion_internal':{}},
      'healthcheck':{'interval':'15s','timeout':'3s','retries':4,'start_period':'15s','test':['CMD','python','-c',"import os,sys,time; p='/tmp/dispatcher-heartbeat'; sys.exit(0 if os.path.exists(p) and time.time()-os.path.getmtime(p)<120 else 1)"]},
      'environment':r.env_dict(container())}},
      'networks':{'ingestion_internal':{'external':True,'name':r.NETWORK}}}

class Fake(r.Runtime):
    def __init__(self, tmp):
        super().__init__(tmp,tmp/'never-read.env',tmp)
        self.current=container(); self.shas=[SHA,SHA]; self.calls=[]; self.activations=[]
        self.fail_step=None; self.routes=dict(r.EXPECTED_ROUTES); self.config=config()
        self.health_fail=False; self.rollback_fail=False
    def latest(self):
        self.calls.append('fetch'); return self.shas.pop(0)
    def inspect(self): return self.current
    def live_routes(self): return self.routes
    def snapshot(self, sha, directory):
        self.calls.append('snapshot:'+sha); p=Path(directory); (p/'deploy').mkdir()
        (p/'deploy/compose.yaml').write_text('synthetic')
        (p/'routes.json').write_text(json.dumps(r.EXPECTED_ROUTES))
        (p/'deploy/routes-contract.json').write_text(json.dumps(r.EXPECTED_ROUTES)); return p
    def run(self,args,**kwargs):
        self.calls.append(args)
        if self.fail_step and self.fail_step in args: raise r.ReconcileError('command_failed')
        if args[:3]==['docker','image','inspect']:
            return json.dumps([{'Id':NEW,'Config':{'User':'10002:10002','Labels':{'org.opencontainers.image.revision':SHA}}}])
        return ''
    def compose(self,source,image,settings,*args):
        assert settings['OUTBOX_POLL_INTERVAL_SECONDS']=='60'
        assert settings['OUTBOX_DISPATCH_DRY_RUN']=='false'
        self.config['services'][r.SERVICE]['image']=image
        return json.dumps(self.config)
    def activate(self,source,image,settings): self.activations.append(image)
    def verify(self,image_id,sha,routes,env,*,rollback=False):
        self.calls.append('verify_rollback' if rollback else 'verify')
        if (rollback and self.rollback_fail) or (not rollback and self.health_fail):
            raise r.ReconcileError('health_failed')

def test_route_validation_closed_duplicate_safe_and_no_drops():
    raw=(BASE/'routes.json').read_text(); assert r.validate_routes(raw)==r.EXPECTED_ROUTES
    missing=json.loads(raw); missing.pop(next(iter(missing)))
    with pytest.raises(r.ReconcileError,match='required_route_missing'): r.validate_routes(json.dumps(missing))
    with pytest.raises(r.ReconcileError,match='duplicate_json_key'): r.validate_routes('{"event":{},"event":{}}')
    for key,value in [('worker_slug','https://foreign.invalid'),('token_env','SUPABASE_SERVICE_ROLE_KEY')]:
        bad=json.loads(raw); bad[next(iter(bad))][key]=value
        with pytest.raises(r.ReconcileError,match='route_not_allowed'): r.validate_routes(json.dumps(bad))
    with pytest.raises(r.ReconcileError,match='live_route_dropped'): r.validate_routes(raw,{'old.route':{}})

@pytest.mark.parametrize('requested',['b'*40,'','main','a'*39,'a'*41])
def test_stale_or_invalid_event_does_not_build(tmp_path,requested):
    f=Fake(tmp_path)
    if requested=='b'*40: assert f.deploy(requested)[0]=='STALE_EVENT_SKIPPED'
    else:
        with pytest.raises(r.ReconcileError,match='invalid_requested_sha'): f.deploy(requested)
    assert not f.activations
    assert not any(isinstance(x,list) and 'build' in x for x in f.calls)

def test_branch_moves_during_build_no_activation(tmp_path):
    f=Fake(tmp_path); f.shas[1]='d'*40
    assert f.deploy()[0]=='DEVELOP_MOVED_SKIPPED'; assert not f.activations
    assert not (tmp_path/'deployment.json').exists()
    assert any(isinstance(x,list) and x[:2]==['docker','run'] for x in f.calls)

def test_exact_image_success_only_after_verification(tmp_path):
    f=Fake(tmp_path); assert f.deploy(SHA)==('DEPLOYED',SHA)
    assert f.activations==[NEW] and f.calls[-1]=='verify'
    receipt=(tmp_path/'deployment.json').read_text()
    assert SHA in receipt and NEW in receipt and 'synthetic-only' not in receipt
    runs=[x for x in f.calls if isinstance(x,list) and x[:2]==['docker','run']]
    assert len(runs)==1 and runs[0][runs[0].index('--network')+1]=='none'
    assert all('NSE_WORKER_TOKEN' not in str(x) for x in f.calls)

def test_already_current_verifies_without_build(tmp_path):
    f=Fake(tmp_path); f.current['Config']['Labels']['org.opencontainers.image.revision']=SHA
    assert f.deploy()[0]=='ALREADY_CURRENT' and not f.activations
    assert not any(isinstance(x,list) and 'build' in x for x in f.calls)

@pytest.mark.parametrize('step',['build','run'])
def test_failed_validation_leaves_prior_container(tmp_path,step):
    f=Fake(tmp_path); f.fail_step=step
    with pytest.raises(r.ReconcileError): f.deploy()
    assert not f.activations

def test_failed_health_restores_prior_image(tmp_path):
    f=Fake(tmp_path); f.health_fail=True
    with pytest.raises(r.ReconcileError,match='activation_failed_prior_image_restored'): f.deploy()
    assert f.activations==[NEW,OLD] and 'verify_rollback' in f.calls
    assert not (tmp_path/'deployment.json').exists()

def test_failed_rollback_never_claims_success(tmp_path):
    f=Fake(tmp_path); f.health_fail=f.rollback_fail=True
    with pytest.raises(r.ReconcileError,match='rollback_failed_operator_required'): f.deploy()

@pytest.mark.parametrize('field,value',[('read_only',False),('user','root'),('cap_add',['SYS_ADMIN']),
 ('ports',['8080:80']),('volumes',['/var/run/docker.sock:/var/run/docker.sock']),('cpus',1),
 ('pids_limit',0),('networks',{'public':{}}),('depends_on',{'api':{}}),('deploy',{'replicas':0}),('healthcheck',{'disable':True})])
def test_hardening_and_dependency_changes_rejected_before_activation(tmp_path,field,value):
    f=Fake(tmp_path); f.config['services'][r.SERVICE][field]=value
    with pytest.raises(r.ReconcileError): f.deploy()
    assert not f.activations

def test_changed_secret_never_printed_or_activated(tmp_path):
    f=Fake(tmp_path); f.config['services'][r.SERVICE]['environment']['NSE_WORKER_TOKEN']='DO_NOT_PRINT'
    with pytest.raises(r.ReconcileError) as error: f.deploy()
    assert str(error.value)=='runtime_env_mismatch' and not f.activations

def test_live_secret_presence_and_security_verified():
    c=container(); r.check_hardening(c)
    c['Config']['Env']=[x for x in c['Config']['Env'] if not x.startswith('NSE_WORKER_TOKEN=')]
    with pytest.raises(r.ReconcileError,match='required_secret_missing'): r.check_hardening(c)

def test_activation_exactly_one_service_no_dependencies_or_orphans(tmp_path):
    rt=r.Runtime(tmp_path,tmp_path/'private.env',tmp_path); calls=[]
    rt.run=lambda args,**kw: calls.append((args,kw)) or ''
    rt.activate(BASE,NEW,{k:'preserved' for k in r.SETTINGS})
    args,kw=calls[0]
    assert args[-1]=='outbox-dispatcher' and '--no-deps' in args and '--no-build' in args
    assert '--remove-orphans' not in args and kw['env']['DISPATCHER_IMAGE']==NEW
    assert all(k not in kw['env'] for k in r.SECRETS)

def test_subprocess_error_does_not_relay_output(monkeypatch,tmp_path):
    monkeypatch.setattr(subprocess,'run',lambda *a,**kw:subprocess.CompletedProcess(a,1,b'SECRET',b'TOKEN'))
    with pytest.raises(r.ReconcileError) as error: r.Runtime(tmp_path,tmp_path/'private',tmp_path).run(['synthetic'])
    assert str(error.value)=='command_failed'

def test_webhook_scope_is_develop_only():
    good={'repository':'sharanravi954mf/Mutual_Fund_Portfolio_App','ref':'refs/heads/develop','head_sha':SHA}
    assert spool.event_sha(json.dumps(good))==SHA
    for patch in [{'ref':'refs/heads/main'},{'repository':'foreign'},{'head_sha':'0'*40},{'head_sha':'$(echo bad)'}]:
        with pytest.raises(ValueError): spool.event_sha(json.dumps(good|patch))

@pytest.mark.parametrize('mutation', ['image','sha','routes','settings','hardening','health'])
def test_actual_post_activation_verification_rejects_drift(tmp_path,monkeypatch,mutation):
    rt=r.Runtime(tmp_path,tmp_path/'private',tmp_path); c=container(); env=r.env_dict(c)
    c['Image']=NEW; c['Config']['Labels']['org.opencontainers.image.revision']=SHA
    routes=dict(r.EXPECTED_ROUTES)
    if mutation=='image': c['Image']=OLD
    if mutation=='sha': c['Config']['Labels']['org.opencontainers.image.revision']='d'*40
    if mutation=='routes': routes.pop(next(iter(routes)))
    if mutation=='settings': c['Config']['Env']=[x if not x.startswith('OUTBOX_POLL_INTERVAL_SECONDS=') else 'OUTBOX_POLL_INTERVAL_SECONDS=5' for x in c['Config']['Env']]
    if mutation=='hardening': c['HostConfig']['ReadonlyRootfs']=False
    if mutation=='health': c['State']['Health']['Status']='unhealthy'
    rt.inspect=lambda:c; rt.live_routes=lambda:routes; monkeypatch.setattr(r.time,'sleep',lambda _:None)
    with pytest.raises(r.ReconcileError): rt.verify(NEW,SHA,r.EXPECTED_ROUTES,env)

def test_webhook_and_timer_share_deployment_lock(tmp_path):
    import threading
    first_entered=threading.Event(); release=threading.Event(); second_entered=threading.Event()
    class First:
        state=tmp_path
        def deploy(self,requested):
            first_entered.set(); assert release.wait(3); return 'FIRST',SHA
    class Second:
        state=tmp_path
        def deploy(self,requested): second_entered.set(); return 'SECOND',SHA
    a=threading.Thread(target=r.reconcile_locked,args=(First(),)); a.start(); assert first_entered.wait(2)
    b=threading.Thread(target=r.reconcile_locked,args=(Second(),)); b.start()
    assert not second_entered.wait(.05)
    release.set(); a.join(2); b.join(2); assert second_entered.is_set()

def test_candidate_route_contract_can_add_reviewed_routes_but_cannot_drop_live():
    previous=dict(r.EXPECTED_ROUTES)
    candidate=previous|{'integration.nse.future_report_requested':{'worker_slug':'nse-future-report-worker','token_env':'NSE_WORKER_TOKEN'}}
    assert r.validate_routes(json.dumps(candidate),previous,candidate)==candidate
    candidate.pop(next(iter(previous)))
    with pytest.raises(r.ReconcileError,match='live_route_dropped'): r.validate_routes(json.dumps(candidate),previous,candidate)

def test_bootstrap_does_not_rewrite_env_or_enable_services():
    script=(BASE/'deploy/bootstrap.sh').read_text()
    assert 'enable' not in '\n'.join(x for x in script.splitlines() if not x.startswith('echo'))
    assert 'docker ' not in script and 'chmod' not in script
    assert 'Group=root' in (BASE/'deploy/moneybowl-outbox-dispatcher-reconcile.service').read_text()
    assert (BASE/'deploy/routes-contract.json').read_text()==(BASE/'routes.json').read_text()
