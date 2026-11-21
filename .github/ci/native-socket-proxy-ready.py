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
# The destination is fixed loopback, never consult system/network proxies.
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
deadline = time.monotonic() + 15
last_failure = 'none'
while True:
    try:
        control = urllib.request.Request(base + '/_native/transport', data=b'{"offline":false}',
            headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
        with opener.open(control, timeout=2) as response:
            state = json.load(response)
        assert state['offline'] is False and state['active'] == 0
        break
    except (OSError, ValueError, AssertionError) as error:
        last_failure = type(error).__name__
        if isinstance(error, urllib.error.URLError):
            last_failure += ' reason=' + type(error.reason).__name__
            if isinstance(error.reason, OSError):
                last_failure += ' errno=' + str(error.reason.errno)
        if isinstance(error, urllib.error.HTTPError):
            last_failure += ' status=' + str(error.code)
        if time.monotonic() > deadline:
            raise SystemExit('Disposable socket gate not ready within15s; last=' + last_failure)
        time.sleep(.2)
request = urllib.request.Request(base + '/api/v1/auth/me',
    headers={'Authorization': 'Bearer ' + token, 'Accept': 'application/json'})
with opener.open(request, timeout=10) as response:
    assert response.status == 200
    payload = json.load(response)
with opener.open(control, timeout=2) as response:
    state = json.load(response)
assert state['forwarded_api'] >= 1
print('Disposable loopback socket gate ready: authenticated fixture API200, forwarding counter verified. Not native app proof.')
