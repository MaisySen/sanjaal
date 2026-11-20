import runpy
verify_frame=runpy.run_path(str(__import__('pathlib').Path(__file__).with_name('memory-video-pixels.py')))['verify_frame']
import subprocess,os,pathlib,time,urllib.request,json,threading
root=pathlib.Path('build/screenshots');root.mkdir(parents=True,exist_ok=True)
device=os.environ['IOS_DEVICE'];bundle='au.fintex.sanjaal'
def run(*args,**kw):return subprocess.run(args,check=True,**kw)
def container():return pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',device,bundle,'data'],text=True).strip())
run('xcrun','simctl','install',device,'build/ios/iphonesimulator/Runner.app')
before=container();app=subprocess.check_output(['xcrun','simctl','get_app_container',device,bundle,'app'],text=True).strip()
# Launch the OS target before the timed interruption. Cold simulator Settings
# startup and its first screenshot can take longer than the test clip itself.
# This does not launch or install Sanjaal, or touch either private app container.
run('xcrun','simctl','launch',device,'com.apple.Preferences')
time.sleep(3)
run('xcrun','simctl','io',device,'screenshot',str(root/'os-prewarm.native.png'))
pids=[]
for phase in ['seed','recover']:
 if phase=='recover':
  assert container()==before
  assert subprocess.check_output(['xcrun','simctl','get_app_container',device,bundle,'app'],text=True).strip()==app
  support=before/'Library'/'Application Support';support.mkdir(parents=True,exist_ok=True)
  (support/'synthetic-marker-recover').write_text('recover')
 with open(root/('launch-'+phase+'.log'),'w') as log:
  run('xcrun','simctl','launch',device,bundle,'--vm-service-host=127.0.0.1','--vm-service-port=57321','--disable-service-auth-codes',stdout=log,stderr=subprocess.STDOUT)
 launch=(root/('launch-'+phase+'.log')).read_text();pid=int(launch.strip().split(':')[-1]);pids.append(pid)
 os.kill(pid,0)
 assert len(set(pids))==len(pids)
 deadline=time.monotonic()+90
 while True:
  try:
   state=json.load(urllib.request.urlopen('http://127.0.0.1:57321/getVM',timeout=2));assert state['result']['type']=='VM';break
  except Exception:
   if time.monotonic()>deadline:raise
   time.sleep(1)
 stop=threading.Event();errors=[]
 def capture():
  seen=set()
  try:
   while not stop.wait(0.3):
    for pending in before.rglob('*.background-pending'):
     if str(pending) in seen:continue
     seen.add(str(pending))
     timeline={'request':time.time()}
     run('xcrun','simctl','launch',device,'com.apple.Preferences')
     timeline['other_launch_done']=time.time()
     time.sleep(2)
     run('xcrun','simctl','io',device,'screenshot',str(root/'memory_video_os_background.native.png'))
     timeline['return_request']=time.time()
     returned=subprocess.check_output(['xcrun','simctl','launch',device,bundle],text=True)
     timeline['return_launch_done']=time.time()
     (root/'background-timeline.json').write_text(json.dumps(timeline))
     assert int(returned.strip().split(':')[-1])==pid, 'background changed app PID'
     os.kill(pid,0)
     time.sleep(1)
     (root/'background.log').write_text('OS Settings then app return; same PID '+str(pid))
     pending.with_suffix('.background-done').write_text('returned')
    for pending in before.rglob('*.native-pending'):
     if str(pending) in seen or pending.with_suffix('.native-done').exists():continue
     seen.add(str(pending));run('xcrun','simctl','io',device,'screenshot',str(root/(pending.stem+'.native.png')))
     verify_frame(root/(pending.stem+'.native.png'),pending.read_text())
     pending.with_suffix('.native-done').write_text('captured')
  except Exception as e:errors.append(str(e))
 thread=threading.Thread(target=capture,daemon=True);thread.start()
 try:
  with open(root/('driver-'+phase+'.log'),'w') as log:
   run('flutter','drive','-d',device,'--driver=test_driver/integration_test.dart','--use-existing-app=http://127.0.0.1:57321/','--no-pub',stdout=log,stderr=subprocess.STDOUT,timeout=240)
 finally:
  stop.set();thread.join(timeout=5)
  for diagnostic in before.rglob('memory-video-*.json'):
   if diagnostic.name in ['memory-video-before.json','memory-video-after.json']:
    (root/diagnostic.name).write_bytes(diagnostic.read_bytes())
 assert not errors,errors
 run('xcrun','simctl','terminate',device,bundle)
 # Simulator app PIDs share the macOS host process namespace. Confirm the
 # observed PID was alive before, and is absent after, explicit termination.
 deadline=time.monotonic()+5
 while True:
  try:os.kill(pid,0)
  except ProcessLookupError:break
  if time.monotonic()>deadline:raise AssertionError('old app PID still exists')
  time.sleep(0.1)
 (root/('terminated-'+phase+'.log')).write_text('PID '+str(pid)+' verified absent')
 print(phase,'PID',pid,'terminated; same container',before,flush=True)
(root/'identity.json').write_text(json.dumps({'pids':pids,'container':str(before),'app':app,'installations':1},indent=2))
