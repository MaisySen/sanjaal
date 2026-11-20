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
historical=subprocess.check_output(['git','show','e45325426b55520613e77c13a2427d8809e94269:app/android/app/src/main/kotlin/au/fintex/sanjaal/MemoryVideoView.kt'],cwd=root,text=True)
check('native-pause-historical',historical,'pause','failed latch missing')
start=protected.index('        // Detach ownership first.')
end=protected.index('        surface.visibility = View.INVISIBLE',start)
a=historical.index('        try { player?.setOnPreparedListener(null);')
b=historical.index('        surface.visibility = View.INVISIBLE',a)
check('native-cleanup-historical',protected[:start]+historical[a:b]+protected[end:],'cleanup','native release not attempted')
needle='if(!disposed && !failed && player === p) {\n                    try { fitVideo();'
assert needle in protected
check('native-late-prepare-mutation',protected.replace(needle,'if(!disposed) {\n                    try { fitVideo();',1),'late','late prepare callback revived retired player')
