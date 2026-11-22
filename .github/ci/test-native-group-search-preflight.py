import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('preflight', Path(__file__).with_name('native-group-search-preflight.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class PreflightTest(unittest.TestCase):
    def setUp(self):
        self.me = {'user': {'username': 'synthetic_member'}, 'features': {'group_ownership': True, 'group_member_removal': True}}
        self.people = {username: {'users': [{'username': username, 'name': name, 'public_id': f'20000000-0000-4000-8000-{i:012d}'}]} for i, (username, name) in enumerate(m.MEMBERS, 1)}
        self.queries = []

    def request(self, path, query):
        self.queries.append((path, query))
        return copy.deepcopy(self.me if path == '/auth/me' else self.people[query['q']])

    def test_checks_real_query_strings_used_by_native_group_helper(self):
        m.check(self.request)
        self.assertEqual(self.queries, [('/auth/me', {}), ('/users/search', {'q': 'asha_e2e'}), ('/users/search', {'q': 'bikram_e2e'})])

    def test_empty_sqlite_underscore_lookup_stops_before_build(self):
        self.people['asha_e2e']['users'] = []
        with self.assertRaises(ValueError):
            m.check(self.request)

    def test_duplicate_or_foreign_identity_cannot_pass(self):
        for field, value in [('username', 'foreign'), ('name', 'Different Person'), ('public_id', 'not-a-uuid')]:
            with self.subTest(field=field):
                self.setUp()
                self.people['asha_e2e']['users'][0][field] = value
                with self.assertRaises(ValueError):
                    m.check(self.request)
        self.setUp()
        self.people['bikram_e2e']['users'][0]['public_id'] = self.people['asha_e2e']['users'][0]['public_id']
        with self.assertRaises(ValueError):
            m.check(self.request)

    def test_ambiguous_member_response_cannot_pass(self):
        self.people['asha_e2e']['users'] *= 2
        with self.assertRaises(ValueError):
            m.check(self.request)

    def test_wrong_account_or_disabled_capability_cannot_pass(self):
        self.me['user']['username'] = 'other'
        with self.assertRaises(ValueError):
            m.check(self.request)
        for flag in ['group_ownership', 'group_member_removal']:
            self.setUp()
            self.me['features'][flag] = False
            with self.assertRaises(ValueError):
                m.check(self.request)


if __name__ == '__main__':
    unittest.main()
