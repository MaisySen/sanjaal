"""Synthetic metadata/bytes contracts. Not device, live API or signature tests."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('manifest', Path(__file__).with_name('candidate_manifest.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class Contracts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.run = {'id': 12, 'status': 'completed', 'conclusion': 'success', 'repository': {'full_name': 'MaisySen/sanjaal'}, 'head_sha': 'a' * 40, 'event': 'push', 'html_url': 'https://github.com/MaisySen/sanjaal/actions/runs/12'}
        self.jobs = {'jobs': [{'name': n, 'run_id': 12, 'head_sha': 'a' * 40, 'status': 'completed', 'conclusion': 'success'} for n in m.GATES]}
        self.artifacts = {'artifacts': []}
        self.evidence = {}
        for i, kind in enumerate(('apk', 'aab'), 1):
            archive = self.root / (kind + '.zip')
            member = 'ci/input.' + kind
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr(member, b'fake input, not an Android binary')
            signed = self.root / ('signed.' + kind)
            signed.write_bytes(b'fake signed output, no signature')
            v = {'package': m.PACKAGE, 'version_name': '0.5.4', 'version_code': 2009, 'abi': 'arm64-v8a', 'certificate_sha256': m.CERTIFICATE, 'input_sha256': m.hashlib.sha256(b'fake input, not an Android binary').hexdigest(), 'source_commit': 'a' * 40, 'ci_run_id': 12, 'ci_url': self.run['html_url'], 'sha256': m.digest(signed), 'bytes': signed.stat().st_size, 'production_api': m.API, 'checks': ['v2_v3_signature', 'stable_certificate', '16kb_zip_and_native_segments', 'no_fixture_or_tunnel_markers', 'backup_disabled', 'not_debuggable', 'bundletool_validate_before_and_after_signing', 'package_version_backup_not_debuggable', 'no_test_markers', 'production_api', 'arm64_elf_16kb', 'jar_signature_all_entries', 'pinned_upload_certificate']}
            verification = self.root / (kind + '.json')
            verification.write_text(json.dumps(v))
            self.evidence[kind] = {'artifact_id': i, 'archive': str(archive), 'member': member, 'signed': str(signed), 'verification': str(verification)}
            self.artifacts['artifacts'].append({'id': i, 'name': 'sanjaal-apk' if kind == 'apk' else 'sanjaal-unsigned-aab-engineering-only', 'digest': 'sha256:' + m.digest(archive), 'expired': False, 'workflow_run': {'id': 12, 'head_sha': 'a' * 40}})

    def make(self):
        with patch.object(m, 'app_tree', return_value='b' * 40), patch.object(m, 'api_tree', return_value='9' * 40):
            return m.build(self.run, self.jobs, self.artifacts, 'fake', 'c' * 40, 'sha256:' + 'd' * 64, self.evidence)

    def alter_report(self, kind, key, value):
        p = Path(self.evidence[kind]['verification'])
        v = json.loads(p.read_text())
        v[key] = value
        p.write_text(json.dumps(v))

    def test_valid_metadata_is_candidate_only(self):
        r = self.make()
        self.assertEqual(r['purpose'], 'PRIVATE_CANDIDATE_NOT_RELEASE_AUTHORIZATION')
        self.assertEqual(len(r['artifacts']), 2)
        self.assertIn('physical-device update/install verification', r['remaining_gates'])
        self.assertNotIn('token', json.dumps(r))

    def test_each_ci_gate_required(self):
        for i in range(5):
            with self.subTest(i=i):
                jobs = copy.deepcopy(self.jobs)
                jobs['jobs'][i]['conclusion'] = 'failure'
                with self.assertRaises(ValueError):
                    m.check_run(self.run, jobs)

    def test_ci_identity_and_trusted_event(self):
        for key, value in [('id', 99), ('head_sha', 'bad'), ('event', 'pull_request'), ('repository', {'full_name': 'other/repo'}), ('status', 'in_progress'), ('html_url', 'https://wrong.invalid')]:
            with self.subTest(key=key):
                run = self.run | {key: value}
                with self.assertRaises(ValueError):
                    m.check_run(run, self.jobs)

    def test_duplicate_or_wrong_job_source(self):
        for jobs in [self.jobs['jobs'] + [self.jobs['jobs'][0]], [j | {'run_id': 14} for j in self.jobs['jobs']], [j | {'head_sha': 'e' * 40} for j in self.jobs['jobs']]]:
            with self.assertRaises(ValueError):
                m.check_run(self.run, {'jobs': jobs})

    def test_archive_and_provider_source_required(self):
        for change in [{'expired': True}, {'digest': 'sha256:' + 'f' * 64}, {'name': 'different'}, {'workflow_run': {'id': 14, 'head_sha': 'a' * 40}}]:
            old = copy.deepcopy(self.artifacts)
            self.artifacts['artifacts'][0].update(change)
            with self.assertRaises(ValueError):
                self.make()
            self.artifacts = old

    def test_original_and_final_bytes_bound(self):
        for key, value in [('input_sha256', 'f' * 64), ('sha256', 'f' * 64), ('bytes', 1), ('package', 'other.app'), ('certificate_sha256', 'f' * 64), ('abi', 'x86_64'), ('ci_run_id', 14), ('source_commit', 'e' * 40), ('production_api', 'https://wrong.invalid')]:
            with self.subTest(key=key):
                p = Path(self.evidence['apk']['verification'])
                old = p.read_text()
                self.alter_report('apk', key, value)
                with self.assertRaises(ValueError):
                    self.make()
                p.write_text(old)

    def test_signing_check_claims_required(self):
        self.alter_report('aab', 'checks', [])
        with self.assertRaises(ValueError):
            self.make()

    def test_old_report_without_input_binding_fails_closed(self):
        p = Path(self.evidence['apk']['verification'])
        v = json.loads(p.read_text())
        del v['input_sha256']
        p.write_text(json.dumps(v))
        with self.assertRaisesRegex(ValueError, 'Finalizer input'):
            self.make()

    def test_version_match(self):
        self.alter_report('aab', 'version_code', 2010)
        with self.assertRaises(ValueError):
            self.make()

    def test_app_tree_change_refused(self):
        with patch.object(m, 'app_tree', side_effect=['b' * 40, 'e' * 40]), patch.object(m, 'api_tree', side_effect=['1' * 40, '2' * 40]):
            with self.assertRaisesRegex(ValueError, 'Neither app tree nor API tree'):
                m.build(self.run, self.jobs, self.artifacts, 'fake', 'c' * 40, 'sha256:' + 'd' * 64, self.evidence)

    def test_new_client_with_identical_api_source_is_bound_not_relabelled(self):
        with patch.object(m, 'app_tree', side_effect=['b' * 40, 'e' * 40]), patch.object(m, 'api_tree', return_value='9' * 40):
            r = m.build(self.run, self.jobs, self.artifacts, 'fake', 'c' * 40, 'sha256:' + 'd' * 64, self.evidence)
        self.assertEqual(r['api']['source_commit'], 'c' * 40)
        self.assertEqual(r['source_commit'], 'a' * 40)
        self.assertEqual(r['api']['source_relation'], 'identical_api_tree')
        self.assertEqual(r['api']['client_api_tree'], r['api']['image_api_tree'])

    def test_unsafe_or_missing_member(self):
        for name in ['../input.apk', '/input.apk', 'not-here.apk', 'input.aab']:
            self.evidence['apk']['member'] = name
            with self.assertRaises(ValueError):
                self.make()

    def test_mutated_archive_rejected(self):
        with Path(self.evidence['apk']['archive']).open('ab') as f:
            f.write(b'tampered')
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            self.make()


if __name__ == '__main__':
    unittest.main()
