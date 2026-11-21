#!/usr/bin/env python3
"""Capture a bounded original HTTPServer bind stack before corrected gate startup."""
import pathlib
import subprocess
import sys

probe = '''import faulthandler, http.server, time
faulthandler.dump_traceback_later(5)
start=time.monotonic()
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),http.server.BaseHTTPRequestHandler)
faulthandler.cancel_dump_traceback_later()
print('Standard HTTPServer numeric bind seconds',round(time.monotonic()-start,3),flush=True)
server.server_close()
'''
log = pathlib.Path('/tmp/ios-standard-bind-probe.log')
with log.open('w') as output:
    child = subprocess.Popen([sys.executable, '-u', '-c', probe], stdout=output, stderr=subprocess.STDOUT)
    try:
        code = child.wait(timeout=12)
    except subprocess.TimeoutExpired:
        child.kill()
        child.wait()
        code = 124
print('Bounded standard-bind probe exit', code)
print(log.read_text())
