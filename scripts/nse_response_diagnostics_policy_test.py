"""Check the migration's immutable snapshot against the single versioned policy."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

class DiagnosticPolicyTest(unittest.TestCase):
    def test_policy_and_database_snapshot_exactly_agree(self):
        policy = json.loads((ROOT / 'supabase/functions/_shared/nse/nse_response_diagnostics_v1.json').read_text())
        sql = (ROOT / 'supabase/migrations/20261002114758_nse_response_diagnostic_policy.sql').read_text()
        self.assertEqual(policy, json.loads(re.search(r'\$json\$(.*?)\$json\$', sql, re.S)[1]))
        self.assertEqual(policy['version'], 1)
        self.assertEqual(len({r['id'] for r in policy['rules']}), 5)
        for rule in policy['rules']:
            self.assertEqual(set(rule), {'id','api','native_status','diagnostic','count','shape','outcome','category','retry','evidence'})
            self.assertTrue(rule['api'].startswith('NSE_'))
            self.assertEqual(rule['count'], 0)
            self.assertEqual(rule['shape'], 'empty_array')
            self.assertIs(rule['retry'], False)
            self.assertTrue(rule['evidence'])
        self.assertNotIn('CREATE TABLE', sql)

if __name__ == '__main__':
    unittest.main()
