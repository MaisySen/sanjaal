#!/usr/bin/env python3
"""Bounded native compiler evidence. Never signs, uploads or runs the app."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import plistlib
import zipfile

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / '.github/ci/reviewed-native-source.json'

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()

def preflight():
    data = json.loads(MANIFEST.read_text())
    assert os.environ.get('GITHUB_REPOSITORY') == 'MaisySen/sanjaal'
    assert os.environ.get('GITHUB_REF') == 'refs/heads/reviewed-native-batch-20261122'
    assert git('rev-parse', 'HEAD') == os.environ['GITHUB_SHA']
    for path, expected in data['trees_and_blobs'].items():
        assert git('rev-parse', 'HEAD:' + path) == expected, path
    subprocess.run(['git', 'diff', '--exit-code'], cwd=ROOT, check=True)
    for name in ['E2E_TOKEN', 'E2E_TOKEN_BASE', 'DART_DEFINES', 'ANDROID_KEYSTORE',
                 'ORG_GRADLE_PROJECT_MYAPP_UPLOAD_STORE_FILE', 'SANJAAL_UNSIGNED_BUNDLE',
                 'APPLE_API_KEY', 'APP_STORE_CONNECT_API_KEY', 'MATCH_PASSWORD']:
        assert not os.environ.get(name), 'Unexpected native/signing input: ' + name
    out = ROOT / 'native-compile-report'
    out.mkdir(exist_ok=True)
    report = dict(data, actual_workflow_source=git('rev-parse', 'HEAD'),
                  native_application_executed=False, binary_published=False,
                  stable_signing_key_used=False, store_or_provider_access=False)
    (out / 'source.json').write_text(json.dumps(report, indent=2) + '\n')

def collect(platform, output):
    out = ROOT / 'native-compile-report'
    report = json.loads((out / 'source.json').read_text())
    artifact = ROOT / output
    toolchain = json.loads((out / 'flutter-version.json').read_text())
    assert toolchain['frameworkVersion'] == '3.50.0'
    report['flutter'] = {k: toolchain[k] for k in ['frameworkVersion', 'frameworkRevision', 'engineRevision', 'dartSdkVersion']}
    if platform == 'android':
        assert artifact.is_file()
        with zipfile.ZipFile(artifact) as archive:
            assert archive.testzip() is None
            names = archive.namelist()
            assert 'AndroidManifest.xml' in names
            assert 'lib/arm64-v8a/libflutter.so' in names
            assert any(n.endswith('shaders/glass_lens.frag') for n in names)
            assert not any(n.startswith('lib/') and n.endswith('.so') and not n.startswith('lib/arm64-v8a/') for n in names)
        report['java'] = (out / 'java-version.txt').read_text().strip()
        payloads = [artifact]
    else:
        assert artifact.is_dir() and (artifact / 'Runner').is_file()
        info = plistlib.loads((artifact / 'Info.plist').read_bytes())
        assert info['CFBundleIdentifier'] == 'au.fintex.sanjaal'
        assert any(p.is_file() for p in artifact.rglob('shaders/glass_lens.frag'))
        report['xcode'] = (out / 'xcode-version.txt').read_text().strip()
        report['simulator_sdk'] = (out / 'simulator-sdk-version.txt').read_text().strip()
        report['bundle_identifier'] = info['CFBundleIdentifier']
        payloads = sorted(p for p in artifact.rglob('*') if p.is_file() and not p.is_symlink())
    records = [{'path': str(p.relative_to(ROOT)), 'bytes': p.stat().st_size,
                'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in payloads]
    report.update(platform=platform, result='COMPILER_ONLY_NOT_A_DELIVERY_CANDIDATE',
                  payload_file_count=len(records), payload_bytes=sum(p['bytes'] for p in records),
                  payload_records_sha256=hashlib.sha256(json.dumps(records, sort_keys=True).encode()).hexdigest(),
                  main_executable=next(p for p in records if p['path'].endswith('.apk') or p['path'].endswith('/Runner')))
    (out / (platform + '.json')).write_text(json.dumps(report, indent=2) + '\n')
    subprocess.run(['git', 'diff', '--exit-code', '--', 'app/pubspec.yaml', 'app/pubspec.lock',
                    'app/android', 'app/ios'], cwd=ROOT, check=True)
    summary = '## Compiler-only engineering validation\n\n```json\n' + json.dumps(report, indent=2) + '\n```\n\n'
    summary += 'No app launch, simulator/device behavior, pixels, timing, design acceptance, stable signing, binary upload or distribution is established.\n'
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as f:
        f.write(summary)
    print(json.dumps(report, indent=2))

if __name__ == '__main__':
    if sys.argv[1:] == ['preflight']:
        preflight()
    elif len(sys.argv) == 4 and sys.argv[1] == 'collect' and sys.argv[2] in ('android', 'ios'):
        collect(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit('Use preflight or collect PLATFORM OUTPUT')
