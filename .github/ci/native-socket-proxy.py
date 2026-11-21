#!/usr/bin/env python3
"""Loopback fixture socket gate. Never use against a production upstream."""
import argparse, http.client, http.server, json, socket, threading, time
from urllib.parse import urlsplit

class State:
    def __init__(self, upstream, token):
        self.upstream, self.token = upstream, token
        self.offline, self.active, self.rejected, self.forwarded_api = False, 0, 0, 0
        self.lock = threading.Condition()

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *_):
        pass
    def answer(self, code, value):
        data = json.dumps(value).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def do_GET(self):
        self.handle_request()
    def do_POST(self):
        self.handle_request()
    def do_PATCH(self):
        self.handle_request()
    def do_DELETE(self):
        self.handle_request()
    def handle_request(self):
        state = self.server.state
        size = int(self.headers.get('Content-Length', '0'))
        if size > 16 * 1024 * 1024:
            self.answer(413, {'error': 'fixture request too large'})
            self.close_connection = True
            return
        body = self.rfile.read(size) if size else None
        if self.path == '/_native/transport':
            if self.command != 'POST' or self.headers.get('Authorization') != 'Bearer ' + state.token:
                self.answer(403, {'error': 'fixture control refused'})
                return
            try:
                value = json.loads(body or b'{}')
            except (ValueError, UnicodeError):
                self.answer(422, {'error': 'invalid fixture control'})
                return
            if not isinstance(value, dict) or type(value.get('offline')) is not bool:
                self.answer(422, {'error': 'offline boolean required'})
                return
            with state.lock:
                state.offline = value['offline']
                end = time.monotonic() + 5
                while state.active and time.monotonic() < end:
                    state.lock.wait(timeout=.05)
                active, rejected, forwarded = state.active, state.rejected, state.forwarded_api
            self.answer(409 if active else 200, {'offline': state.offline, 'active': active, 'rejected': rejected, 'forwarded_api': forwarded})
            return
        with state.lock:
            if state.offline and self.path.startswith('/api/v1/'):
                state.rejected += 1
                self.close_connection = True
                try:
                    self.connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                return
            state.active += 1
            if self.path.startswith('/api/v1/'):
                state.forwarded_api += 1
        upstream = None
        try:
            upstream = http.client.HTTPConnection(state.upstream.hostname, state.upstream.port, timeout=10)
            headers = {k:v for k,v in self.headers.items() if k.lower() not in ['host','connection']}
            upstream.request(self.command, self.path, body, headers)
            response = upstream.getresponse()
            payload = response.read(16 * 1024 * 1024 + 1)
            if len(payload) > 16 * 1024 * 1024:
                raise ValueError('fixture response too large')
            self.send_response(response.status)
            for key, value in response.getheaders():
                if key.lower() not in ['connection','transfer-encoding','content-length']:
                    self.send_header(key, value)
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except (OSError, http.client.HTTPException, ValueError):
            self.close_connection = True
        finally:
            if upstream:
                upstream.close()
            with state.lock:
                state.active -= 1
                state.lock.notify_all()

class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, state):
        self.state = state
        super().__init__(address, Handler)

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--port', required=True, type=int)
    p.add_argument('--upstream', required=True)
    p.add_argument('--token-file', required=True)
    args = p.parse_args()
    upstream = urlsplit(args.upstream)
    if upstream.scheme != 'http' or upstream.hostname not in ['127.0.0.1','localhost'] or not upstream.port:
        p.error('only an explicit loopback fixture upstream is allowed')
    with open(args.token_file) as f:
        token = f.read().strip()
    if not token:
        p.error('empty fixture control token')
    Server(('127.0.0.1', args.port), State(upstream, token)).serve_forever()
