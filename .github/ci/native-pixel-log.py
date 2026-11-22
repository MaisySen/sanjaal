"""Bounded synthetic iOS simulator pixels for validation logs, not phone delivery.

No artifact upload or cache export is used by this candidate. The workflow runs
only against its disposable local API. Each packet is below the log-line limit.
Consumers must reassemble every part and check the byte count and SHA256 before
opening the PNG. A packet does not establish that a run or a test passed.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import struct

NAMES = (
    'native_ios_home.png',
    'native_ios_first_use_intro.png',
    'native_ios_first_use_native_keyboard.png',
    'native_ios_first_use_registration_validation.png',
    'native_ios_first_use_recovery_validation.png',
    'native_ios_settings.png',
    'native_ios_native_device_access.png',
    'native_ios_chat_native_keyboard_ready.png',
    'native_ios_group_created.png',
    'native_ios_group_remove_confirm.png',
    'native_ios_group_removed.png',
    'native_ios_group_owner_confirm.png',
    'native_ios_group_transferred.png',
    'native_ios_group_member_role.png',
    'ios-diagnostic-native.png',
)
MAX_IMAGE = 4 * 1024 * 1024
MAX_TOTAL = 12 * 1024 * 1024
CHUNK = 24000


def emit(root, require_complete=True):
    total = 0
    found = set()
    for name in NAMES:
        path = root / name
        if not path.exists():
            continue
        if path.is_symlink() or not path.is_file():
            raise ValueError('Expected a regular native PNG')
        size = path.stat().st_size
        if not 24 <= size <= MAX_IMAGE or total + size > MAX_TOTAL:
            raise ValueError('Native evidence exceeds its byte bound')
        data = path.read_bytes()
        if len(data) != size:
            raise ValueError('Native capture changed while reading')
        if data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
            raise ValueError('Native evidence is not PNG')
        width, height = struct.unpack('>II', data[16:24])
        if not (0 < width <= 5000 and 0 < height <= 5000):
            raise ValueError('Unexpected native frame dimensions')
        parts = (size + CHUNK - 1) // CHUNK
        digest = hashlib.sha256(data).hexdigest()
        for part in range(parts):
            packet = dict(schema=1, name=name, size=size, width=width,
                          height=height, sha256=digest,
                          part=part, parts=parts,
                          png=base64.b64encode(data[part*CHUNK:(part+1)*CHUNK]).decode('ascii'))
            print('SANJAAL_NATIVE_PIXEL ' + json.dumps(packet, separators=(',', ':')), flush=True)
        found.add(name)
        total += size
    print('Native frame manifest: ' + json.dumps(sorted(found)), flush=True)
    missing = sorted(set(NAMES) - found)
    print('Native evidence mode: ' + ('complete required' if require_complete else 'failed-run partial diagnostics'), flush=True)
    print('Missing declared native frames: ' + json.dumps(missing), flush=True)
    if require_complete and missing:
        raise ValueError('Required native captures are missing: ' + ', '.join(missing))


if __name__ == '__main__':
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise SystemExit('Only the synthetic CI fixture may emit native evidence')
    project = Path(__file__).resolve().parents[2]
    exit_file = project / 'app/ios-driver-exit.txt'
    complete = exit_file.is_file() and exit_file.read_text().strip() == '0'
    emit(project / 'app/build/screenshots', require_complete=complete)
