"""Unit contracts with fake Android tools. Not APK signature or device evidence."""
import base64,contextlib,hashlib,importlib.util,io,json,shutil,struct,sys,tempfile,unittest,zipfile
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('preview',Path(__file__).with_name('finalize_phone_preview.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def elf(alignment=16384):
 b=bytearray(120);b[:6]=b'\x7fELF\x02\x01';struct.pack_into('<H',b,18,183);struct.pack_into('<Q',b,32,64);struct.pack_into('<HH',b,54,56,1);struct.pack_into('<I',b,64,1);struct.pack_into('<Q',b,112,alignment)
 return bytes(b)+m.PRODUCTION_API
class Contracts(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.d=Path(self.temp.name)
  self.inp=self.d/'input.apk';self.out=self.d/'final.apk'
  with zipfile.ZipFile(self.inp,'w') as z:
   for n,b in [('AndroidManifest.xml',b'fake'),('classes.dex',b'fake'),('lib/arm64-v8a/libapp.so',elf())]:z.writestr(n,b)
  self.run={'id':1,'status':'completed','conclusion':'success','head_sha':'abc','html_url':'https://example.invalid/fixture'}
  self.jobs={'jobs':[{'name':n,'status':'completed','conclusion':'success'} for n in ['api','app','ios','emulator','bundle']]}
  self.evidence={'run_id':1,'head_sha':'abc','apk_sha256':m.sha(self.inp)}
  self.cert=m.CERT;self.abi='arm64-v8a';self.backup='0x0';self.debug=''
 def tools(self,*args):
  args=[str(x) for x in args];cmd=Path(args[0]).name
  if cmd=='aapt':
   if args[2]=='badging':return "package: name='au.fintex.sanjaal' versionCode='2007' versionName='0.5.2'\nnative-code: '"+self.abi+"'"
   return 'android:allowBackup(0x01010280)=(type 0x12)'+self.backup+'\n'+self.debug
  if cmd=='zipalign':
   if '-f' in args:shutil.copy(args[-2],args[-1])
   return ''
  if cmd=='apksigner' and args[1]=='sign':shutil.copy(args[-1],args[args.index('--out')+1]);return ''
  if cmd=='apksigner':return 'Signer #1 certificate SHA-256 digest: '+self.cert+'\nVerified using v2 scheme (APK Signature Scheme v2): true\nVerified using v3 scheme (APK Signature Scheme v3): true'
  raise AssertionError('Unexpected command')
 def execute(self):
  files={'ci-run':self.run,'ci-jobs':self.jobs,'artifact-evidence':self.evidence}
  argv=['finalizer','--input',str(self.inp),'--output',str(self.out),'--build-tools',str(self.d),'--version','0.5.2','--version-code','2007']
  for n,obj in files.items():
   p=self.d/(n+'.json');p.write_text(json.dumps(obj));argv+=['--'+n,str(p)]
  k=self.d/'fake-key';k.write_text(base64.b64encode(b'NOT-A-REAL-KEY').decode()+'\n');pw=self.d/'fake-password';pw.write_text('NOT-A-REAL-PASSWORD')
  argv+=['--keystore-base64-file',str(k),'--password-file',str(pw)]
  with patch.object(sys,'argv',argv),patch.object(m,'call',self.tools),contextlib.redirect_stdout(io.StringIO()):m.main()
 def fails(self):
  with self.assertRaises(AssertionError):self.execute()
  self.assertFalse(self.out.exists())
 def test_complete_fake_contract_creates_report_checksum_and_does_not_overwrite(self):
  self.execute();report=json.loads(self.out.with_suffix('.verification.json').read_text());self.assertEqual(report['sha256'],m.sha(self.out));self.assertEqual(report['input_sha256'],m.sha(self.inp));self.assertTrue((self.d/'SHA256SUMS.txt').exists())
  with self.assertRaises(AssertionError):self.execute()
 def test_non_green_run_is_not_signable(self):self.run['conclusion']='failure';self.fails()
 def test_missing_bundle_gate_is_not_signable(self):self.jobs['jobs']=self.jobs['jobs'][:-1];self.fails()
 def test_failed_bundle_gate_is_not_signable(self):self.jobs['jobs'][-1]['conclusion']='failure';self.fails()
 def test_failed_emulator_gate_is_not_signable(self):self.jobs['jobs'][-2]['conclusion']='failure';self.fails()
 def test_wrong_source_is_not_signable(self):self.evidence['head_sha']='other';self.fails()
 def test_wrong_input_digest_is_not_signable(self):self.evidence['apk_sha256']='bad';self.fails()
 def test_wrong_abi_is_not_signable(self):self.abi='x86_64';self.fails()
 def test_backup_enabled_is_not_signable(self):self.backup='0xffffffff';self.fails()
 def test_debuggable_is_not_signable(self):self.debug='android:debuggable(0x0101000f)=(type 0x12)0xffffffff';self.fails()
 def test_wrong_final_certificate_is_not_signable(self):self.cert='bad';self.fails()
 def test_native_4kb_load_alignment_is_rejected(self):
  with self.assertRaises(AssertionError):m.check_elf16k(elf(4096),'fixture.so')
 def test_non_elf_native_payload_is_rejected(self):
  with self.assertRaises(AssertionError):m.check_elf16k(b'fake','fixture.so')
 def test_fixture_marker_is_not_signable(self):
  with zipfile.ZipFile(self.inp,'a') as z:z.writestr('forbidden',b'local-e2e')
  self.evidence['apk_sha256']=m.sha(self.inp);self.fails()
if __name__=='__main__':unittest.main()
