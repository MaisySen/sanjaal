# Contract only: fake adb tests the fixed CI bridge. Never device/media proof.
import tempfile,pathlib,subprocess,os,socket,time,urllib.request,urllib.error,json,shutil
source=pathlib.Path(__file__).with_name('native_media.php')
php=os.environ.get('PHPBIN') or shutil.which('php')
if not php:raise RuntimeError('PHP CLI required')
with tempfile.TemporaryDirectory() as td:
 d=pathlib.Path(td);server=d/'api/tests/E2E';server.mkdir(parents=True);shutil.copy(source,server/'index.php');(d/'token.txt').write_text('fixture-only')
 adb=d/'platform-tools/adb';adb.parent.mkdir();adb.write_text('''#!/usr/bin/env python3
import sys
from pathlib import Path
args=sys.argv[1:];root=Path(__file__).parents[1]
with (root/'calls').open('a') as f:f.write(' '.join(args)+'\\n')
mode=(root/'mode').read_text()
if args[:3]==['shell','pm','grant'] and mode=='grantfail':sys.exit(1)
if args[:3]==['shell','dumpsys','window']:print('mCurrentFocus=Window{abc u0 '+('wrong.app/Activity' if mode=='unfocused' else 'au.fintex.sanjaal/.MainActivity')+'}')
''');adb.chmod(0o700);(d/'mode').write_text('focused')
 sock=socket.socket();sock.bind(('127.0.0.1',0));port=sock.getsockname()[1];sock.close()
 env=os.environ|{'E2E_NATIVE_INPUT':'1','E2E_JWKS_FILE':str(d/'jwks.json'),'ANDROID_HOME':str(d)}
 proc=subprocess.Popen([php,'-S',f'127.0.0.1:{port}','-t',str(server)],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 def request(body,auth=True):
  req=urllib.request.Request(f'http://127.0.0.1:{port}/',data=json.dumps(body).encode(),headers={'Content-Type':'application/json','Authorization':'Bearer fixture-only' if auth else 'wrong'})
  try:r=urllib.request.urlopen(req,timeout=20);return r.status,json.load(r)
  except urllib.error.HTTPError as e:return e.code,json.load(e)
 try:
  time.sleep(.3)
  assert request({'action':'prepare'})[0]==200
  for action in ['camera','recording','gallery','poster','composer','story']:assert request({'action':action})[0]==200
  assert request({'action':'prepare'},False)[0]==403
  for bad in ['shell','../private','gallery;evil','wipe']:assert request({'action':bad})[0]==422
  (d/'mode').write_text('grantfail');assert request({'action':'prepare'})[0]==502
  (d/'mode').write_text('unfocused');assert request({'action':'camera'})[0]==502
  calls=(d/'calls').read_text();assert 'pm grant au.fintex.sanjaal android.permission.CAMERA' in calls
  assert 'pm grant au.fintex.sanjaal android.permission.POST_NOTIFICATIONS' in calls
  assert '/sdcard/Pictures/sanjaal-fixture.png' in calls and 'wipe' not in calls
  print('Fixed media bridge: authentication, action whitelist, failed permissions and native focus enforced')
 finally:proc.terminate();proc.wait()
