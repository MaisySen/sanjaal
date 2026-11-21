import unittest,importlib.util,tempfile,datetime,plistlib,hashlib
from pathlib import Path
from unittest.mock import patch
s=importlib.util.spec_from_file_location('gate',Path(__file__).with_name('ios_release_gate.py'));g=importlib.util.module_from_spec(s);s.loader.exec_module(g)
class SignatureContract(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.app=self.root/'Runner.app';self.app.mkdir();(self.app/'Frameworks/A.framework').mkdir(parents=True);self.cert=b'SYNTHETIC_CERT_NOT_SIGNING_MATERIAL';self.digest=hashlib.sha256(self.cert).hexdigest()
  self.ent={'application-identifier':g.TEAM+'.'+g.PACKAGE,'get-task-allow':False};self.profile={'TeamIdentifier':[g.TEAM],'DeveloperCertificates':[self.cert],'ExpirationDate':datetime.datetime(2027,11,21),'Entitlements':dict(self.ent)};self.calls=[]
 def tearDown(self):self.temp.cleanup()
 def output(self,cmd,**kw):
  self.calls.append(cmd)
  if cmd[0]=='security':return plistlib.dumps(self.profile)
  return plistlib.dumps(self.ent)
 def run(self,result=None):
  # unittest calls run itself; use check() for gate execution below.
  return super().run(result)
 def check(self):
  def execute(cmd,**kw):
   self.calls.append(cmd)
   if '--extract-certificates' in cmd:Path(cmd[cmd.index('--extract-certificates')+1]+'0').write_bytes(self.cert)
  with patch.object(g.subprocess,'run',side_effect=execute),patch.object(g.subprocess,'check_output',side_effect=self.output):return g.verify_signatures(self.app,self.digest)
 def test_commands_include_nested_deep_strict_and_cert_binding(self):
  self.assertTrue(self.check()['profile_certificate_match']);self.assertTrue(any('--deep' in x and '--strict' in x for x in self.calls));self.assertTrue(any(str(self.app/'Frameworks/A.framework') in x for x in self.calls))
 def test_wrong_team(self):
  self.profile['TeamIdentifier']=['OTHER']
  with self.assertRaises(ValueError):self.check()
 def test_ad_hoc_profile(self):
  self.profile['ProvisionedDevices']=['fixture']
  with self.assertRaises(ValueError):self.check()
 def test_enterprise_profile(self):
  self.profile['ProvisionsAllDevices']=True
  with self.assertRaises(ValueError):self.check()
 def test_expired_profile(self):
  self.profile['ExpirationDate']=datetime.datetime(2020,1,1)
  with self.assertRaises(ValueError):self.check()
 def test_debuggable_profile(self):
  self.profile['Entitlements']['get-task-allow']=True
  with self.assertRaises(ValueError):self.check()
 def test_debuggable_signature(self):
  self.ent['get-task-allow']=True
  with self.assertRaises(ValueError):self.check()
 def test_wrong_signature_certificate(self):
  self.digest='0'*64
  with self.assertRaises(ValueError):self.check()
if __name__=='__main__':unittest.main()
