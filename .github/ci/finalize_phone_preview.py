#!/usr/bin/env python3
"""Sign and check one CI-produced ARM64 preview. Does not publish or deploy.

Key/password values are read from private files, never command arguments or logs.
The required evidence is downloaded from the selected successful CI run, including
jobs with all four required checks; the input APK digest must match that download.
"""
import argparse,base64,hashlib,json,os,re,subprocess,tempfile,zipfile
from pathlib import Path

PACKAGE='au.fintex.sanjaal'
CERT='e6d401f11358c43e232921a088401b9c2aa25eabe4ecd972e17954220d9783a7'
PRODUCTION_API=b'https://sanjaal-api.onrender.com/api/v1'
FORBIDDEN=[b'trycloudflare',b'local-e2e',b'10.0.2.2',b'E2E_TOKEN']

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def call(*args):return subprocess.check_output([str(x) for x in args],stderr=subprocess.STDOUT).decode()
def check_payload(path,tool,version,code):
    badging=call(tool/'aapt','dump','badging',path)
    assert re.search(r"package: name='"+re.escape(PACKAGE)+r"' versionCode='"+str(code)+r"' versionName='"+re.escape(version)+"'",badging),'Wrong package or version'
    assert "native-code: 'arm64-v8a'" in badging and "'armeabi-v7a'" not in badging and "'x86_64'" not in badging,'Wrong ABI'
    manifest=call(tool/'aapt','dump','xmltree',path,'AndroidManifest.xml')
    assert not re.search(r'android:debuggable[^\n]*0xffffffff',manifest),'Debuggable APK'
    assert re.search(r'android:allowBackup[^\n]*0x0(?:\s|$)',manifest),'Backup must be disabled'
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None,'APK CRC failure'
        names=z.namelist()
        assert 'AndroidManifest.xml' in names and 'classes.dex' in names and 'lib/arm64-v8a/libapp.so' in names,'Incomplete APK'
        for name in names:
            if name.endswith('/'):continue
            blob=z.read(name)
            assert not any(term in blob for term in FORBIDDEN),'Test endpoint/token/tunnel marker in '+name
        assert PRODUCTION_API in z.read('lib/arm64-v8a/libapp.so'),'Production API not found in app code'
    return badging

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['input','output','ci-run','ci-jobs','artifact-evidence','keystore-base64-file','password-file','build-tools','version']:
        p.add_argument('--'+name,required=True)
    p.add_argument('--version-code',required=True,type=int)
    a=p.parse_args();inp=Path(a.input);out=Path(a.output);tool=Path(a.build_tools)
    assert not out.exists(),'Refuse to overwrite an existing final artifact'
    run=json.loads(Path(a.ci_run).read_text());jobs=json.loads(Path(a.ci_jobs).read_text())['jobs'];evidence=json.loads(Path(a.artifact_evidence).read_text())
    assert run['status']=='completed' and run['conclusion']=='success','Selected CI run did not pass'
    assert run['head_sha']==evidence['head_sha'] and run['id']==evidence['run_id'],'Artifact/run source mismatch'
    for name in ['api','app','ios','emulator']:
        match=[j for j in jobs if j['name']==name]
        assert len(match)==1 and match[0]['status']=='completed' and match[0]['conclusion']=='success','Missing or failed '+name+' gate'
    assert sha(inp)==evidence['apk_sha256'],'Input differs from downloaded CI artifact'
    check_payload(inp,tool,a.version,a.version_code)
    out.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='sanjaal-final-') as tmp:
        tmp=Path(tmp);key=tmp/'upload.p12';key.write_bytes(base64.b64decode(Path(a.keystore_base64_file).read_text().strip(),validate=True));key.chmod(0o600)
        aligned=tmp/'aligned.apk';candidate=tmp/'signed.apk'
        call(tool/'zipalign','-P','16','-f','4',inp,aligned)
        call(tool/'apksigner','sign','--ks',key,'--ks-key-alias','upload','--ks-pass','file:'+a.password_file,'--key-pass','file:'+a.password_file,'--out',candidate,aligned)
        result=call(tool/'apksigner','verify','--verbose','--print-certs',candidate)
        assert 'Signer #1 certificate SHA-256 digest: '+CERT in result,'Wrong signing identity'
        assert 'Verified using v2 scheme (APK Signature Scheme v2): true' in result and 'Verified using v3 scheme (APK Signature Scheme v3): true' in result,'Missing v2/v3 signature'
        call(tool/'zipalign','-c','-P','16','4',candidate)
        check_payload(candidate,tool,a.version,a.version_code)
        os.replace(candidate,out)
    report={'package':PACKAGE,'version_name':a.version,'version_code':a.version_code,'abi':'arm64-v8a','certificate_sha256':CERT,'sha256':sha(out),'bytes':out.stat().st_size,'source_commit':run['head_sha'],'ci_run_id':run['id'],'ci_url':run['html_url'],'production_api':PRODUCTION_API.decode(),'checks':['all_four_ci_jobs_passed','input_archive_digest','package_version_abi','v2_v3_signature','stable_certificate','16kb_alignment','no_fixture_or_tunnel_markers','production_api','backup_disabled','not_debuggable']}
    out.with_suffix('.verification.json').write_text(json.dumps(report,indent=2)+'\n')
    out.parent.joinpath('SHA256SUMS.txt').write_text(report['sha256']+'  '+out.name+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
