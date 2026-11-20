import runpy
verify_frame=runpy.run_path(str(__import__('pathlib').Path(__file__).with_name('memory-video-pixels.py')))['verify_frame']
import pathlib,subprocess,sys,threading,time
phase,timeout,*cmd=sys.argv[1:];stop=threading.Event();errors=[]
root=pathlib.Path('build/screenshots');root.mkdir(parents=True,exist_ok=True)
def adb(*args):return subprocess.check_output(['adb',*args])
def capture():
 seen=set()
 try:
  while not stop.wait(0.3):
   try:listing=adb('shell','run-as','au.fintex.sanjaal','ls','files').decode().splitlines()
   except subprocess.CalledProcessError:continue
   if 'memory_video_os.background-pending' in listing and 'background' not in seen:
    seen.add('background')
    pid=adb('shell','pidof','au.fintex.sanjaal').decode().strip()
    subprocess.run(['adb','shell','input','keyevent','KEYCODE_HOME'],check=True)
    time.sleep(2)
    (root/'memory_video_os_background.native.png').write_bytes(adb('exec-out','screencap','-p'))
    subprocess.run(['adb','shell','am','start','-n','au.fintex.sanjaal/.MainActivity'],check=True)
    time.sleep(1)
    assert adb('shell','pidof','au.fintex.sanjaal').decode().strip()==pid, 'background changed app process'
    (root/'process_death_background.log').write_text('OS HOME then activity return; same PID '+pid)
    subprocess.run(['adb','shell','run-as','au.fintex.sanjaal','touch','files/memory_video_os.background-done'],check=True)
   for name in listing:
    if not name.startswith('memory_video_') or not name.endswith('.native-pending') or name in seen:continue
    seen.add(name);stem=name.removesuffix('.native-pending')
    image=root/(stem+'.native.png')
    image.write_bytes(adb('exec-out','screencap','-p'))
    verify_frame(image,adb('shell','run-as','au.fintex.sanjaal','cat','files/'+name).decode())
    subprocess.run(['adb','shell','run-as','au.fintex.sanjaal','touch','files/'+stem+'.native-done'],check=True)
 except Exception as e:errors.append(str(e))
thread=threading.Thread(target=capture,daemon=True);thread.start()
try:
 result=subprocess.run(cmd,timeout=int(timeout))
finally:stop.set();thread.join(timeout=5)
if errors:raise RuntimeError(errors)
sys.exit(result.returncode)
