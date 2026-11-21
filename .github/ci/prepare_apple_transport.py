#!/usr/bin/env python3
"""Prepare the existing Sanjaal Apple identity for macOS, never create an identity.

Local-only operator step. The certificate and key must already exist in the given
private directory. No credentials are logged or committed. Creates only three
GitHub environment secrets; caller must delete all three after the archive ends.

macOS security import rejected default OpenSSL PKCS12 transport. The proven
transport uses PBE-SHA1-3DES for key and certificate and SHA1 for its MAC, with a
fresh nonempty transport password. These algorithms are transport compatibility,
not app cryptography. Never silently fall back to the default format.
"""
import argparse, base64, json, secrets, subprocess, tempfile
from pathlib import Path

REPO = 'MaisySen/sanjaal'
ENV = 'sanjaal-private-signing'
NAMES = {'SANJAAL_SIGNING_P12_B64', 'SANJAAL_SIGNING_PROFILE_B64', 'SANJAAL_SIGNING_P12_PASSWORD'}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--identity-dir', required=True, type=Path)
    args = parser.parse_args()
    existing = json.loads(subprocess.check_output(['gh', 'api', f'repos/{REPO}/environments/{ENV}/secrets']))
    if existing['total_count']:
        raise SystemExit('Refusing to overwrite existing environment secrets. Inspect and clean up first.')
    root = args.identity_dir
    password = secrets.token_urlsafe(32)
    with tempfile.TemporaryDirectory(prefix='sanjaal-transport-') as tmp:
        tmp = Path(tmp)
        tmp.chmod(0o700)
        pw = tmp / 'password'
        pw.write_text(password)
        pw.chmod(0o600)
        p12 = tmp / 'identity.p12'
        subprocess.run(['openssl', 'pkcs12', '-export', '-inkey', str(root / 'distribution-key.pem'), '-in', str(root / 'distribution.pem'), '-name', 'Sanjaal Apple Distribution', '-keypbe', 'PBE-SHA1-3DES', '-certpbe', 'PBE-SHA1-3DES', '-macalg', 'sha1', '-out', str(p12), '-passout', 'file:' + str(pw)], check=True, capture_output=True)
        subprocess.run(['openssl', 'pkcs12', '-in', str(p12), '-passin', 'file:' + str(pw), '-noout'], check=True, capture_output=True)
        values = {'SANJAAL_SIGNING_P12_B64': base64.b64encode(p12.read_bytes()), 'SANJAAL_SIGNING_PROFILE_B64': base64.b64encode((root / 'Sanjaal-Private-AppStore-20261121.mobileprovision').read_bytes()), 'SANJAAL_SIGNING_P12_PASSWORD': password.encode()}
        installed = []
        try:
            for name, value in values.items():
                subprocess.run(['gh', 'secret', 'set', name, '--repo', REPO, '--env', ENV], input=value, check=True, capture_output=True)
                installed.append(name)
        except Exception:
            for name in installed:
                subprocess.run(['gh', 'secret', 'delete', name, '--repo', REPO, '--env', ENV], capture_output=True)
            raise SystemExit('Transport setup failed. Partial secrets were removed; inspect environment before retry.')
    actual = json.loads(subprocess.check_output(['gh', 'api', f'repos/{REPO}/environments/{ENV}/secrets']))
    if {item['name'] for item in actual['secrets']} != NAMES:
        raise SystemExit('Environment secret names differ. Inspect before using.')
    print('Three archive-only secrets prepared. Local transport files removed. Delete all three after archive ends.')

if __name__ == '__main__':
    main()
