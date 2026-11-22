"""Check the disposable native API before spending time compiling the app."""
import http.client
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlencode

MEMBERS = (('asha_e2e', 'Asha Gurung'), ('bikram_e2e', 'Bikram Test'))


def check(get_json):
    current = get_json('/auth/me', {})
    if current.get('user', {}).get('username') != 'synthetic_member':
        raise ValueError('Native preflight requires its synthetic account')
    features = current.get('features', {})
    if any(features.get(k) is not True for k in ['group_ownership', 'group_member_removal']):
        raise ValueError('Native group capabilities are not enabled in the isolated API')
    ids = set()
    for username, name in MEMBERS:
        result = get_json('/users/search', {'q': username})
        users = result.get('users')
        if not isinstance(users, list) or len(users) != 1:
            raise ValueError('Native group member lookup must return exactly one synthetic match')
        user = users[0]
        if user.get('username') != username or user.get('name') != name:
            raise ValueError('Native group member identity does not match the fixture')
        public_id = user.get('public_id', '')
        if not isinstance(public_id, str) or not re.fullmatch(r'[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}', public_id) or public_id in ids:
            raise ValueError('Native group member public identity is invalid or repeated')
        ids.add(public_id)


def main(token_file):
    token = Path(token_file).read_text().strip()
    if not token or '\n' in token or '\r' in token:
        raise ValueError('Native fixture credential is unavailable')

    def get_json(path, query):
        # Fixed loopback endpoint. No redirects or external destinations.
        connection = http.client.HTTPConnection('127.0.0.1', 8002, timeout=8)
        try:
            target = '/api/v1' + path + ('?' + urlencode(query) if query else '')
            connection.request('GET', target, headers={'Authorization': 'Bearer ' + token, 'Accept': 'application/json'})
            response = connection.getresponse()
            body = response.read(100001)
            if response.status != 200 or len(body) > 100000:
                raise ValueError('Native preflight API did not return a bounded success')
            result = json.loads(body)
            if not isinstance(result, dict):
                raise ValueError('Native preflight response is not an object')
            return result
        finally:
            connection.close()
    check(get_json)
    print('Native group search preflight passed for the isolated fixture', flush=True)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) == 2 else '/tmp/ios-e2e/token.txt')
