"""Fake tool/archive unit contracts only. Not AAB signing or device evidence."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('bundle', Path(__file__).with_name('finalize_play_bundle.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class Contracts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.p = Path(self.tmp.name) / 'fake.aab'
        self.entries = {'BundleConfig.pb': b'fake', 'base/manifest/AndroidManifest.xml': b'fake', 'base/lib/arm64-v8a/libapp.so': m.preview.PRODUCTION_API}
        self.manifest = '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="au.fintex.sanjaal" android:versionName="0.5.2" android:versionCode="7"><uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36"/><application android:allowBackup="false"/></manifest>'
        self.run = {'id': 2, 'status': 'completed', 'conclusion': 'success', 'head_sha': 'synthetic'}
        self.jobs = {'jobs': [{'name': n, 'status': 'completed', 'conclusion': 'success'} for n in ['api', 'app', 'ios', 'emulator', 'bundle']]}
        self.write()

    def write(self):
        with zipfile.ZipFile(self.p, 'w') as z:
            for n, b in self.entries.items():
                z.writestr(n, b)
        self.evidence = {'run_id': 2, 'head_sha': 'synthetic', 'aab_sha256': m.preview.sha(self.p)}

    def payload(self, unsigned=True):
        self.write()
        with patch.object(m, 'call', return_value=self.manifest), patch.object(m.preview, 'check_elf16k'):
            return m.payload(self.p, 'fake-tool', '0.5.2', 7, unsigned=unsigned)

    def test_fake_valid_payload_contract(self):
        self.assertEqual(self.payload(), {'min_sdk': '24', 'target_sdk': '36'})

    def test_each_ci_gate_required(self):
        for index in range(5):
            with self.subTest(index=index):
                jobs = copy.deepcopy(self.jobs)
                jobs['jobs'][index]['conclusion'] = 'failure'
                with self.assertRaises(AssertionError):
                    m.check_ci(self.run, jobs, self.evidence, self.p)

    def test_source_mismatch_rejected(self):
        self.evidence['head_sha'] = 'different'
        with self.assertRaises(AssertionError):
            m.check_ci(self.run, self.jobs, self.evidence, self.p)

    def test_download_digest_mismatch_rejected(self):
        self.evidence['aab_sha256'] = 'different'
        with self.assertRaises(AssertionError):
            m.check_ci(self.run, self.jobs, self.evidence, self.p)

    def test_signed_input_rejected(self):
        self.entries['META-INF/UPLOAD.RSA'] = b'fake'
        with self.assertRaises(AssertionError):
            self.payload()

    def test_tunnel_test_token_and_local_api_rejected(self):
        for term in m.preview.FORBIDDEN:
            with self.subTest(term=term):
                self.entries['base/assets/bad'] = term
                with self.assertRaises(AssertionError):
                    self.payload()

    def test_missing_production_api_rejected(self):
        self.entries['base/lib/arm64-v8a/libapp.so'] = b'fake'
        with self.assertRaises(AssertionError):
            self.payload()

    def test_unexpected_abi_rejected(self):
        self.entries['base/lib/x86_64/libapp.so'] = b'fake'
        with self.assertRaises(AssertionError):
            self.payload()

    def test_wrong_package_version_and_backup_rejected(self):
        original = self.manifest
        for before, after in [('au.fintex.sanjaal', 'wrong.app'), ('versionCode="7"', 'versionCode="8"'), ('versionName="0.5.2"', 'versionName="0.0.1"'), ('allowBackup="false"', 'allowBackup="true"'), ('allowBackup="false"', 'allowBackup="false" android:debuggable="true"')]:
            with self.subTest(after=after):
                self.manifest = original.replace(before, after)
                with self.assertRaises(AssertionError):
                    self.payload()
        self.manifest = original

    def test_real_bad_elf_rejected(self):
        with self.assertRaises(AssertionError):
            m.preview.check_elf16k(b'fake', 'fake.so')


if __name__ == '__main__':
    unittest.main()
