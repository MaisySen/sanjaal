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
    'native_ios_settings.png',
    'native_ios_native_device_access.png',
    'native_ios_chat_native_keyboard_ready.png',
    'ios-diagnostic-native.png',
)
MAX_IMAGE = 4 * 1024 * 1024
MAX_TOTAL = 12 * 1024 * 1024
CHUNK = 24000


def emit(root):
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
    if 'native_ios_native_device_access.png' not in found:
        raise ValueError('Required native Device access capture is missing')


if __name__ == '__main__':
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise SystemExit('Only the synthetic CI fixture may emit native evidence')
    emit(Path(__file__).resolve().parents[2] / 'app/build/screenshots')
