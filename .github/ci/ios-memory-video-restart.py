import subprocess,os,pathlib,time,urllib.request,json,threading
root=pathlib.Path('build/screenshots');root.mkdir(parents=True,exist_ok=True)
device=os.environ['IOS_DEVICE'];bundle='au.fintex.sanjaal'
def run(*args,**kw):return subprocess.run(args,check=True,**kw)
def container():return pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',device,bundle,'data'],text=True).strip())
run('xcrun','simctl','install',device,'build/ios/iphonesimulator/Runner.app')
before=container();app=subprocess.check_output(['xcrun','simctl','get_app_container',device,bundle,'app'],text=True).strip()
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
    for pending in before.rglob('*.native-pending'):
     if str(pending) in seen or pending.with_suffix('.native-done').exists():continue
     seen.add(str(pending));run('xcrun','simctl','io',device,'screenshot',str(root/(pending.stem+'.native.png')))
     pending.with_suffix('.native-done').write_text('captured')
  except Exception as e:errors.append(str(e))
 thread=threading.Thread(target=capture,daemon=True);thread.start()
 try:
  with open(root/('driver-'+phase+'.log'),'w') as log:
   run('flutter','drive','-d',device,'--driver=test_driver/integration_test.dart','--use-existing-app=http://127.0.0.1:57321/','--no-pub',stdout=log,stderr=subprocess.STDOUT,timeout=240)
 finally:stop.set();thread.join(timeout=5)
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
