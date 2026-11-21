import unittest,importlib.util,copy
from pathlib import Path
s=importlib.util.spec_from_file_location('gate',Path(__file__).with_name('ios_release_gate.py'));g=importlib.util.module_from_spec(s);s.loader.exec_module(g)
class Gate(unittest.TestCase):
 def toolchain(self):return {'xcode':'26.6','ios_sdk':'26.5','deployment_target':'15.0','flutter_revision':'ab2912035e160d9cad6306df307576da6128ebdb','engine_revision':'371f77202a73e8dff57a8b3bff75bca55c090aee','candidate_plugins_compile_success':True}
 def audience(self):return {'app_id':'6837257828','fetched_at_utc':'2026-11-21T21:00:00Z','groups':[{'isInternalGroup':True,'hasAccessToAllBuilds':False,'publicLinkEnabled':False}],'unverified_tester_identifiers':[]}
 def test_current_sdk_not_called_latest(self):
  r=g.check_toolchain(self.toolchain(),'2026-11-22');self.assertEqual(r['accepted_minimum'],26);self.assertFalse(r['future_27_ready'])
 def test_future_sdk_floor(self):
  with self.assertRaises(ValueError):g.check_toolchain(self.toolchain(),'2027-04-01')
 def test_future27(self):
  x=self.toolchain();x.update(xcode='27.2',ios_sdk='27.2');self.assertTrue(g.check_toolchain(x,'2027-04-01')['future_27_ready'])
 def test_compatibility_is_not_version_inference(self):
  x=self.toolchain();x['candidate_plugins_compile_success']=False
  with self.assertRaises(ValueError):g.check_toolchain(x,'2026-11-22')
 def test_unreviewed_flutter(self):
  x=self.toolchain();x['flutter_revision']='changed'
  with self.assertRaises(ValueError):g.check_toolchain(x,'2026-11-22')
 def test_current_live_automatic_group_blocks(self):
  x=self.audience();x['groups'][0]['hasAccessToAllBuilds']=True
  with self.assertRaises(ValueError):g.check_audience_snapshot(x)
 def test_missing_allbuild_setting_blocks(self):
  x=self.audience();del x['groups'][0]['hasAccessToAllBuilds']
  with self.assertRaises(ValueError):g.check_audience_snapshot(x)
 def test_unverified_tester_blocks(self):
  x=self.audience();x['unverified_tester_identifiers']=['unknown@example.invalid']
  with self.assertRaises(ValueError):g.check_audience_snapshot(x)
 def test_public_link_blocks(self):
  x=self.audience();x['groups'][0]['publicLinkEnabled']=True
  with self.assertRaises(ValueError):g.check_audience_snapshot(x)
 def test_external_audience_not_assumed(self):
  x=self.audience();x['groups'][0]['isInternalGroup']=False
  with self.assertRaises(ValueError):g.check_audience_snapshot(x)
 def test_wrong_app(self):
  x=self.audience();x['app_id']='other'
  with self.assertRaises(ValueError):g.check_audience_snapshot(x)
 def test_technical_manual_audience_only(self):self.assertTrue(g.check_audience_snapshot(self.audience()))
if __name__=='__main__':unittest.main()
