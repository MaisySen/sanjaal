"""Actual Kotlin adapter negatives, with deterministic Android/Flutter fakes."""
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[2]
p=root/'app/android/app/src/main/kotlin/au/fintex/sanjaal/MemoryVideoView.kt'
protected=p.read_text()
def check(name,source,mode,reason):
 try:
  p.write_text(source)
  result=subprocess.run(['bash',str(root/'.github/ci/test-native-memory-video.sh'),mode],cwd=root,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=90)
  (root/(name+'.log')).write_text(result.stdout)
  assert result.returncode!=0 and reason in result.stdout,(name,result.returncode,result.stdout)
  print('EXPECTED FAILURE',name,reason)
 finally:p.write_text(protected)
historical=subprocess.check_output(['git','show','5fe152925708c10391e7bced50e1c07cfd73e27d:app/android/app/src/main/kotlin/au/fintex/sanjaal/MemoryVideoView.kt'],cwd=root,text=True)
check('native-setup-historical',historical,'setup','native release not attempted')
check('native-prepared-historical',historical,'prepared','IllegalStateException: seek')
