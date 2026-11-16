# Local contract checks with a fake adb; these are not emulator/device evidence.
import tempfile, pathlib, subprocess,os,socket,time,urllib.request,urllib.error,json,shutil
source=pathlib.Path(__file__).with_name('native_input.php')
php=os.environ.get('PHPBIN') or shutil.which('php')
if not php: raise RuntimeError('PHP CLI is required for the fixture contract test')
with tempfile.TemporaryDirectory() as td:
 d=pathlib.Path(td); server=d/'api/tests/E2E';server.mkdir(parents=True);shutil.copy(source,server/'index.php');(d/'token.txt').write_text('fixture-only')
 adb=d/'platform-tools/adb';adb.parent.mkdir();adb.write_text('''#!/usr/bin/env python3
import sys,os
from pathlib import Path
args=sys.argv[1:];root=Path(__file__).parents[1]
with (root/'calls').open('a') as f:f.write(' '.join(args)+'\\n')
mode=(root/'mode').read_text()
if args[:3]==['shell','pm','grant'] and mode=='grantfail':sys.exit(1)
if args[:3]==['shell','dumpsys','window']:print('mCurrentFocus=Window{abc u0 '+('com.google.android.permissioncontroller/GrantActivity' if mode=='unfocused' else 'au.fintex.sanjaal/.MainActivity')+'}')
if args[:2]==['exec-out','cat']:print('<hierarchy fixture="true"/>')
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
  status,body=request({'prepare_notifications':True});assert status==200 and body['app_focused'];print('ready requires focused expected fixture: pass')
  status,body=request({'x':1,'y':1});assert status==200;print('bounded native tap retained: pass')
  assert request({'x':-1,'y':1})[0]==422;assert request({'prepare_notifications':True},False)[0]==403;print('input/auth restrictions retained: pass')
  (d/'mode').write_text('grantfail');status,body=request({'prepare_notifications':True});assert status==502 and not body['ok'];print('permission failure cannot pass: pass')
  (d/'mode').write_text('unfocused');status,body=request({'prepare_notifications':True});assert status==502 and not body['app_focused'];print('foreign native focus cannot pass: pass')
  calls=(d/'calls').read_text();assert 'pm grant au.fintex.sanjaal android.permission.POST_NOTIFICATIONS' in calls;assert 'input tap -' not in calls;print('fixed-package command contract: pass')
 finally:proc.terminate();proc.wait()
