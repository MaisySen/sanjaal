#!/usr/bin/env python3
"""Inspect the current-run APK without signing, publishing or claiming install proof."""
import hashlib, importlib.util, json, os, pathlib, re, subprocess
root=pathlib.Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('preview',root/'.github/ci/finalize_phone_preview.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
app=root/'app'
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
if os.environ.get('GITHUB_SHA') != head: raise SystemExit('Exact source mismatch')
if subprocess.check_output(['git','diff','--name-only','HEAD'],cwd=root,text=True).strip():
    raise SystemExit('Tracked source changed during package')
version=re.search(r'^version: ([^+]+)\+(\d+)$',(app/'pubspec.yaml').read_text(),re.M)
if not version: raise SystemExit('Version missing')
tools=pathlib.Path(os.environ['ANDROID_HOME'])/'build-tools'
choices=[p for p in tools.iterdir() if (p/'aapt').is_file() and (p/'apksigner').is_file()]
if not choices: raise SystemExit('Android inspection tools missing')
tool=max(choices,key=lambda p:[int(x) if x.isdigit() else 0 for x in re.split('[.-]',p.name)])
apks=list((app/'build/app/outputs/flutter-apk').glob('*.apk'))
if len(apks)!=1:raise SystemExit('Expected one ARM64 engineering APK')
apk=apks[0]
m.check_payload(apk,tool,version[1],int(version[2]))
subprocess.run([str(tool/'zipalign'),'-c','-P','16','4',str(apk)],check=True)
sig=subprocess.check_output([str(tool/'apksigner'),'verify','--verbose','--print-certs',str(apk)],text=True)
if 'Android Debug' not in sig:raise SystemExit('Expected generated engineering debug certificate')
print(json.dumps({'source_sha':head,'apk_sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),
 'bytes':apk.stat().st_size,'version':version[1],'version_code':int(version[2]),
 'signing':'generated debug key, engineering only, not approved for user installation',
 'physical_install_tested':False,'artifact_uploaded':False,'stable_signing':False,
 'checks':['exact source','package version ABI','16KB native segments and zip alignment','CRC','production endpoint','no fixture markers','backup disabled','not debuggable','signature verifies']},indent=2))
