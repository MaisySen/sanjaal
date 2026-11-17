#!/usr/bin/env python3
"""Prepare a private signed engineering AAB. Never uploads or publishes.

Requires all five CI jobs and a digest from the actual downloaded artifact.
Play package ownership, accepted upload certificate, version-code uniqueness,
store declarations and approval remain separate gates. ARM64 only.
"""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

spec = importlib.util.spec_from_file_location('preview', Path(__file__).with_name('finalize_phone_preview.py'))
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)
BUNDLETOOL_SHA = 'a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29'
BUNDLETOOL_URL = 'https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar'
ANDROID = '{http://schemas.android.com/apk/res/android}'
MIN_UPGRADE_CODE = 2008  # Held stable-key ARM64 APK is code2007.


def call(*args):
    p = subprocess.run([str(x) for x in args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if p.returncode:
        # No raw subprocess logs: private input filenames may be present.
        raise RuntimeError('Local bundle verification/signing command failed: ' + Path(str(args[0])).name)
    return p.stdout.decode()


def check_ci(run, jobs, evidence, inp):
    assert run['status'] == 'completed' and run['conclusion'] == 'success', 'CI did not pass'
    assert run['head_sha'] == evidence['head_sha'] and run['id'] == evidence['run_id'], 'CI source mismatch'
    assert preview.sha(inp) == evidence['aab_sha256'], 'AAB differs from actual downloaded artifact'
    for name in ['api', 'app', 'ios', 'emulator', 'bundle']:
        found = [j for j in jobs['jobs'] if j['name'] == name]
        assert len(found) == 1 and found[0]['status'] == 'completed' and found[0]['conclusion'] == 'success', 'Missing/failed CI gate: ' + name


def payload(path, bundletool, version, code, unsigned=False):
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None, 'Bundle CRC error'
        names = z.namelist()
        assert len(names) == len(set(names)), 'Duplicate bundle entries'
        assert {'BundleConfig.pb', 'base/manifest/AndroidManifest.xml', 'base/lib/arm64-v8a/libapp.so'}.issubset(names), 'Incomplete bundle'
        assert not unsigned or not any(n.upper().startswith('META-INF/') and n.upper().endswith(('.RSA', '.DSA', '.EC', '.SF')) for n in names), 'Input bundle must be unsigned'
        libs = [n for n in names if n.startswith('base/lib/') and n.endswith('.so')]
        assert libs and all(n.startswith('base/lib/arm64-v8a/') for n in libs), 'Unexpected bundle ABI'
        for n in names:
            if n.endswith('/'):
                continue
            b = z.read(n)
            assert not any(term in b for term in preview.FORBIDDEN), 'Test endpoint/token/tunnel marker: ' + n
            if n in libs:
                preview.check_elf16k(b, n)
        assert preview.PRODUCTION_API in z.read('base/lib/arm64-v8a/libapp.so'), 'Production API absent'
    call('java', '-jar', bundletool, 'validate', '--bundle=' + str(path))
    manifest = ET.fromstring(call('java', '-jar', bundletool, 'dump', 'manifest', '--bundle=' + str(path)))
    assert manifest.get('package') == preview.PACKAGE, 'Wrong package'
    assert manifest.get(ANDROID + 'versionName') == version and manifest.get(ANDROID + 'versionCode') == str(code), 'Wrong version'
    app = manifest.find('application')
    assert app is not None and app.get(ANDROID + 'debuggable', 'false') == 'false', 'Debuggable bundle'
    assert app.get(ANDROID + 'allowBackup') == 'false', 'Backup must be disabled'
    sdk = manifest.find('uses-sdk')
    return {'min_sdk': sdk.get(ANDROID + 'minSdkVersion'), 'target_sdk': sdk.get(ANDROID + 'targetSdkVersion')}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['input', 'output', 'ci-run', 'ci-jobs', 'artifact-evidence', 'keystore-base64-file', 'password-file', 'bundletool', 'version']:
        p.add_argument('--' + name, required=True)
    p.add_argument('--version-code', required=True, type=int)
    a = p.parse_args()
    inp, out = Path(a.input), Path(a.output)
    assert a.version_code >= MIN_UPGRADE_CODE, 'Bundle must upgrade held stable-key APK code2007'
    assert not out.exists() and not out.with_suffix('.verification.json').exists(), 'Refuse to overwrite final artifact/report'
    assert preview.sha(a.bundletool) == BUNDLETOOL_SHA, 'Wrong bundletool binary'
    run = json.loads(Path(a.ci_run).read_text())
    check_ci(run, json.loads(Path(a.ci_jobs).read_text()), json.loads(Path(a.artifact_evidence).read_text()), inp)
    sdk = payload(inp, a.bundletool, a.version, a.version_code, unsigned=True)
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='sanjaal-bundle-') as tmp:
        tmp = Path(tmp)
        key = tmp / 'upload.p12'
        key.write_bytes(base64.b64decode(Path(a.keystore_base64_file).read_text().strip(), validate=True))
        key.chmod(0o600)
        key_info = call('keytool', '-list', '-v', '-keystore', key, '-storepass:file', a.password_file, '-alias', 'upload')
        fingerprint = preview.CERT.upper()
        assert 'PrivateKeyEntry' in key_info and any(re.sub('[^0-9A-Fa-f]', '', line.split('SHA256:', 1)[1]).upper() == fingerprint for line in key_info.splitlines() if 'SHA256:' in line), 'Wrong upload key'
        candidate = tmp / 'signed.aab'
        call('java', '-m', 'jdk.jartool/sun.security.tools.jarsigner.Main', '-keystore', key, '-storetype', 'PKCS12', '-storepass:file', a.password_file, '-keypass:file', a.password_file, '-sigalg', 'SHA256withRSA', '-digestalg', 'SHA-256', '-signedjar', candidate, inp, 'upload')
        check = call('java', '-m', 'jdk.jartool/sun.security.tools.jarsigner.Main', '-verify', '-verbose', '-certs', candidate)
        assert 'jar verified.' in check and 'unsigned entries' not in check.lower() and 'jar is unsigned' not in check.lower(), 'Bundle signature or coverage failed'
        cert = call('keytool', '-printcert', '-jarfile', candidate)
        certs = [re.sub('[^0-9A-Fa-f]', '', line.split('SHA256:', 1)[1]).upper() for line in cert.splitlines() if 'SHA256:' in line]
        assert certs == [fingerprint], 'Wrong or multiple bundle signer certificates'
        assert payload(candidate, a.bundletool, a.version, a.version_code) == sdk
        os.replace(candidate, out)
    report = {'package': preview.PACKAGE, 'version_name': a.version, 'version_code': a.version_code, 'abi': 'arm64-v8a', **sdk, 'certificate_sha256': preview.CERT, 'sha256': preview.sha(out), 'input_sha256': preview.sha(inp), 'bytes': out.stat().st_size, 'source_commit': run['head_sha'], 'ci_run_id': run['id'], 'ci_url': run['html_url'], 'bundletool_url': BUNDLETOOL_URL, 'bundletool_sha256': BUNDLETOOL_SHA, 'checks': ['five_ci_jobs_passed', 'downloaded_input_digest', 'bundletool_validate_before_and_after_signing', 'package_version_backup_not_debuggable', 'no_test_markers', 'production_api', 'arm64_elf_16kb', 'jar_signature_all_entries', 'pinned_upload_certificate'], 'distribution': 'PRIVATE_ENGINEERING_ONLY_NO_UPLOAD', 'unverified': ['Play app ownership and upload certificate acceptance', 'Play version code availability', 'Play policy/declarations/permission review', 'device-generated APK packaging and physical-device installation', 'other Android ABIs', 'live service readiness']}
    out.with_suffix('.verification.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
