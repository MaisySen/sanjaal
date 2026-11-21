import unittest,importlib.util,copy,datetime,tempfile,zipfile,plistlib,hashlib,json,subprocess
from unittest.mock import patch
from pathlib import Path
s=importlib.util.spec_from_file_location('gate',Path(__file__).with_name('ios_release_gate.py'));g=importlib.util.module_from_spec(s);s.loader.exec_module(g)
class Gate(unittest.TestCase):
 def now(self):return datetime.datetime(2026,11,21,21,1,tzinfo=datetime.timezone.utc)
 def toolchain(self):return {'xcode':'26.6','ios_sdk':'26.5','deployment_target':'15.0','flutter_revision':'ab2912035e160d9cad6306df307576da6128ebdb','engine_revision':'371f77202a73e8dff57a8b3bff75bca55c090aee','candidate_plugins_compile_success':True}
 def audience(self):return {'app_id':'6837257828','fetched_at_utc':'2026-11-21T21:00:00Z','groups':[{'isInternalGroup':True,'hasAccessToAllBuilds':False,'publicLinkEnabled':False}],'unverified_tester_identifiers':[],'complete_groups_and_testers':True}
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
  with self.assertRaises(ValueError):g.check_audience_snapshot(x,self.now())
 def test_missing_allbuild_setting_blocks(self):
  x=self.audience();del x['groups'][0]['hasAccessToAllBuilds']
  with self.assertRaises(ValueError):g.check_audience_snapshot(x,self.now())
 def test_unverified_tester_blocks(self):
  x=self.audience();x['unverified_tester_identifiers']=['unknown@example.invalid']
  with self.assertRaises(ValueError):g.check_audience_snapshot(x,self.now())
 def test_public_link_blocks(self):
  x=self.audience();x['groups'][0]['publicLinkEnabled']=True
  with self.assertRaises(ValueError):g.check_audience_snapshot(x,self.now())
 def test_external_audience_not_assumed(self):
  x=self.audience();x['groups'][0]['isInternalGroup']=False
  with self.assertRaises(ValueError):g.check_audience_snapshot(x,self.now())
 def test_wrong_app(self):
  x=self.audience();x['app_id']='other'
  with self.assertRaises(ValueError):g.check_audience_snapshot(x,self.now())
 def test_technical_manual_audience_only(self):self.assertTrue(g.check_audience_snapshot(self.audience(),self.now()))


class Archive(unittest.TestCase):
 now=Gate.now
 toolchain=Gate.toolchain
 audience=Gate.audience
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.ipa=self.root/'candidate.ipa';self.envelope=self.root/'provider.zip';self.build=2014
  self.repo=self.root/'repo';self.repo.mkdir();subprocess.run(['git','init','-q',str(self.repo)],check=True);wf=self.repo/'.github/workflows/release.yml';wf.parent.mkdir(parents=True);wf.write_text('name: fixture\n');subprocess.run(['git','-C',str(self.repo),'add','.'],check=True);subprocess.run(['git','-C',str(self.repo),'-c','user.name=fixture','-c','user.email=fixture@example.invalid','commit','-qm','fixture'],check=True);self.head=subprocess.check_output(['git','-C',str(self.repo),'rev-parse','HEAD'],text=True).strip();self.blob=subprocess.check_output(['git','-C',str(self.repo),'rev-parse','HEAD:.github/workflows/release.yml'],text=True).strip()
  self.policy={'source_sha':'a4b99e2385add30b159cd7edb3c04b827a387cb2','orchestration_sha':self.head,'workflow_blob':self.blob,'workflow_sha256':g.sha(wf),'workflow_path':'.github/workflows/release.yml'}
  self.pl={'CFBundleIdentifier':g.PACKAGE,'CFBundleVersion':'2014','CFBundleShortVersionString':'0.5.9','MinimumOSVersion':'15.0'}
  self.repack()
  self.manifest={**self.policy,'build':2014,'version':'0.5.9','run_id':42,'job_id':43,'attempt':1,'ipa_sha256':g.sha(self.ipa),'toolchain':self.toolchain()}
  self.wrap()
  self.p={'manifest':self.manifest,'run':{'id':42,'head_sha':self.head,'repository':{'full_name':'MaisySen/sanjaal'},'status':'completed','run_attempt':1},'job':{'id':43,'run_id':42,'head_sha':self.head,'status':'completed','conclusion':'success','run_attempt':1},'artifact':{'workflow_run':{'id':42,'head_sha':self.head},'expired':False,'digest':'sha256:'+g.sha(self.envelope)}}
  self.log='git log -1 --format=%H\n2026-11-21T21:00:00Z '+self.policy['source_sha']
 def tearDown(self):self.tmp.cleanup()
 def repack(self,extra=None,binary=None):
  with zipfile.ZipFile(self.ipa,'w') as z:
   root='Payload/Runner.app/'
   for n,b in {'Info.plist':plistlib.dumps(self.pl),'PrivacyInfo.xcprivacy':plistlib.dumps({'NSPrivacyAccessedAPITypes':[]}),'embedded.mobileprovision':b'fixture-only','_CodeSignature/CodeResources':b'fixture-only','Frameworks/App.framework/App':binary if binary is not None else g.ENDPOINT}.items():z.writestr(root+n,b)
   for n,b in (extra or {}).items():z.writestr(n,b)
 def wrap(self):
  with zipfile.ZipFile(self.envelope,'w') as z:z.writestr('compile-manifest.json',json.dumps(self.manifest));z.writestr('archive.cms',b'fake-encrypted-container')
 def check(self):return g.check_provenance(self.p,self.envelope,self.ipa,self.policy,self.log,self.repo)
 def test_synthetic_archive_structure(self):self.assertFalse(g.check_archive(self.ipa,2014,'0.5.9')['privacy_completeness_reviewed'])
 def test_version_rejected(self):
  self.pl['CFBundleVersion']='2013';self.repack()
  with self.assertRaises(ValueError):g.check_archive(self.ipa,2014,'0.5.9')
 def test_unanswered_legal_not_encoded(self):
  self.pl['ITSAppUsesNonExemptEncryption']=False;self.repack()
  with self.assertRaises(ValueError):g.check_archive(self.ipa,2014,'0.5.9')
 def test_archive_traversal(self):
  self.repack({'../elsewhere':b'bad'})
  with self.assertRaises(ValueError):g.check_archive(self.ipa,2014,'0.5.9')
 def test_fixture_marker(self):
  self.repack({'Payload/Runner.app/anything':b'E2E_TOKEN'})
  with self.assertRaises(ValueError):g.check_archive(self.ipa,2014,'0.5.9')
 def test_production_endpoint(self):
  self.repack(binary=b'not production')
  with self.assertRaises(ValueError):g.check_archive(self.ipa,2014,'0.5.9')
 def test_provider_binding(self):self.assertEqual(self.check()['build'],2014)
 def test_wrong_attempt(self):
  self.p['job']['run_attempt']=2
  with self.assertRaises(ValueError):self.check()
 def test_actual_checkout_not_echoed(self):
  self.log='source is '+self.policy['source_sha']
  with self.assertRaises(ValueError):self.check()
 def test_changed_ipa(self):
  self.repack({'Payload/Runner.app/extra':b'change'})
  with self.assertRaises(ValueError):self.check()
 def test_changed_manifest_not_in_envelope(self):
  self.p['manifest']['build']=2015
  with self.assertRaises(ValueError):self.check()
 def test_stale_audience(self):
  with self.assertRaises(ValueError):g.check_audience_snapshot(self.audience(),self.now()+datetime.timedelta(minutes=6))
 def test_build_uniqueness_live_snapshot(self):
  b={'app_id':g.APP,'fetched_at_utc':'2026-11-21T21:00:00Z','all_versions_enumerated':True,'build_numbers':[2013,2014]}
  with self.assertRaises(ValueError):g.check_build_number(b,2014,self.now())
 def test_full_gate_invokes_signature_and_never_grants_permission(self):
  b={'app_id':g.APP,'fetched_at_utc':'2026-11-21T21:00:00Z','all_versions_enumerated':True,'build_numbers':[2013]}
  with patch.object(g,'verify_signatures',return_value={'mocked':True}) as verify:
   out=g.technical_preflight(provenance=self.p,provider_archive=self.envelope,ipa=self.ipa,policy=self.policy,executed_log=self.log,audience=self.audience(),builds=b,now=self.now(),expected_cert_sha256='a'*64,repo=self.repo)
   verify.assert_called_once();self.assertFalse(out['upload_allowed']);self.assertFalse(out['permission_verified'])
 def test_full_gate_toolchain_failure_before_signature(self):
  self.manifest['toolchain']['candidate_plugins_compile_success']=False;self.wrap();self.p['artifact']['digest']='sha256:'+g.sha(self.envelope)
  b={'app_id':g.APP,'fetched_at_utc':'2026-11-21T21:00:00Z','all_versions_enumerated':True,'build_numbers':[2013]}
  with patch.object(g,'verify_signatures') as verify:
   with self.assertRaises(ValueError):g.technical_preflight(provenance=self.p,provider_archive=self.envelope,ipa=self.ipa,policy=self.policy,executed_log=self.log,audience=self.audience(),builds=b,now=self.now(),expected_cert_sha256='a'*64,repo=self.repo)
   verify.assert_not_called()
if __name__=='__main__':unittest.main()
