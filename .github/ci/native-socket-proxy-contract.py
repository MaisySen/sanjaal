#!/usr/bin/env python3
"""Real sockets, isolated fixture only. This is not a native app/device test."""
import http.client
import http.server
import importlib.util
import json
import pathlib
import threading
import unittest

spec = importlib.util.spec_from_file_location('native_gate', pathlib.Path(__file__).with_name('native-socket-proxy.py'))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

class Upstream(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def do_GET(self):
        body = b'{"data":[]}'
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_):
        pass

class Contract(unittest.TestCase):
    def setUp(self):
        self.up = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Upstream)
        self.up.daemon_threads = True
        self.state = gate.State(gate.urlsplit('http://127.0.0.1:' + str(self.up.server_port)), 'synthetic-control')
        self.proxy = gate.Server(('127.0.0.1', 0), self.state)
        self.threads = [threading.Thread(target=s.serve_forever) for s in [self.up, self.proxy]]
        for t in self.threads:
            t.start()
        self.client = http.client.HTTPConnection('127.0.0.1', self.proxy.server_port, timeout=2)
    def tearDown(self):
        self.client.close()
        for s in [self.up, self.proxy]:
            s.shutdown()
            s.server_close()
        for t in self.threads:
            t.join()
    def control(self, value, token='synthetic-control'):
        self.client.request('POST', '/_native/transport', json.dumps({'offline': value}), {'Authorization':'Bearer ' + token})
        response = self.client.getresponse()
        return response.status, json.loads(response.read())
    def test_unauthorized_and_invalid_control_does_not_block_api(self):
        self.assertEqual(self.control(True, 'wrong')[0], 403)
        self.assertFalse(self.state.offline)
        self.assertEqual(self.control('true')[0], 422)
        self.assertFalse(self.state.offline)
        for invalid in ['{', '[]', 'null']:
            self.client.request('POST', '/_native/transport', invalid, {'Authorization':'Bearer synthetic-control'})
            r = self.client.getresponse()
            self.assertEqual(r.status, 422)
            r.read()
            self.assertFalse(self.state.offline)
        self.client.request('GET', '/api/v1/ping')
        r = self.client.getresponse()
        self.assertEqual(r.status, 200)
        r.read()
        self.assertEqual(self.state.forwarded_api, 1)
    def test_offline_closes_api_sockets_and_reconnect_preserves_same_client(self):
        self.client.request('GET', '/api/v1/calls/incoming')
        r = self.client.getresponse()
        self.assertEqual(r.status, 200)
        r.read()
        self.assertEqual(self.control(True)[1]['active'], 0)
        for _ in range(3):
            with self.assertRaises(http.client.RemoteDisconnected):
                self.client.request('GET', '/api/v1/calls/incoming')
                self.client.getresponse()
        # Control and fixture-native media remain reachable while API sockets fail.
        self.client.request('GET', '/ios-native-fixture.mp4')
        r = self.client.getresponse()
        self.assertEqual(r.status, 200)
        r.read()
        state = self.control(False)[1]
        self.assertEqual(state['rejected'], 3)
        self.assertEqual(state['forwarded_api'], 1)
        self.client.request('GET', '/api/v1/calls/incoming')
        r = self.client.getresponse()
        self.assertEqual(r.status, 200)
        r.read()
        self.assertEqual(self.state.forwarded_api, 2)

if __name__ == '__main__':
    unittest.main()
