#!/usr/bin/env python3
"""Bounded disposable-runner readiness, before native compilation."""
import json
import pathlib
import sys
import time
import urllib.error
import urllib.request

token = pathlib.Path(sys.argv[1]).read_text().strip()
assert token
base = 'http://127.0.0.1:8002'
deadline = time.monotonic() + 15
while True:
    try:
        control = urllib.request.Request(base + '/_native/transport', data=b'{"offline":false}',
            headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
        with urllib.request.urlopen(control, timeout=2) as response:
            state = json.load(response)
        assert state['offline'] is False and state['active'] == 0
        break
    except (OSError, ValueError, AssertionError):
        if time.monotonic() > deadline:
            raise SystemExit('Disposable socket gate not ready within15s')
        time.sleep(.2)
request = urllib.request.Request(base + '/api/v1/auth/me',
    headers={'Authorization': 'Bearer ' + token, 'Accept': 'application/json'})
with urllib.request.urlopen(request, timeout=10) as response:
    assert response.status == 200
    payload = json.load(response)
with urllib.request.urlopen(control, timeout=2) as response:
    state = json.load(response)
assert state['forwarded_api'] >= 1
print('Disposable loopback socket gate ready: authenticated fixture API200, forwarding counter verified. Not native app proof.')
