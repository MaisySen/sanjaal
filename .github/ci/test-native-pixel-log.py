"""Synthetic packet tests. These images are not native validation evidence."""
import base64
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

spec = importlib.util.spec_from_file_location('native_pixels', Path(__file__).with_name('native-pixel-log.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def synthetic_png(padding=0):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
            + chunk(b'tEXt', b'synthetic\0' + b'x' * padding)
            + chunk(b'IDAT', zlib.compress(b'\0\xff\0\0')) + chunk(b'IEND', b''))


class NativePixelsTest(unittest.TestCase):
    def test_packets_round_trip_exact_bytes_and_digest(self):
        self.assert_round_trip(synthetic_png())

    def test_multipart_round_trip_exact_bytes_and_digest(self):
        self.assert_round_trip(synthetic_png(module.CHUNK * 2), minimum_parts=3)

    def assert_round_trip(self, data, minimum_parts=1):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'native_ios_native_device_access.png').write_bytes(data)
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                module.emit(root, require_complete=False)
            rows = [json.loads(line.removeprefix('SANJAAL_NATIVE_PIXEL '))
                    for line in out.getvalue().splitlines() if line.startswith('SANJAAL_NATIVE_PIXEL ')]
            self.assertEqual(len(rows), rows[0]['parts'])
            self.assertGreaterEqual(len(rows), minimum_parts)
            self.assertEqual([row['part'] for row in rows], list(range(len(rows))))
            actual = b''.join(base64.b64decode(row['png'], validate=True) for row in sorted(rows, key=lambda row: row['part']))
            self.assertEqual(actual, data)
            self.assertEqual(hashlib.sha256(actual).hexdigest(), rows[0]['sha256'])
            self.assertEqual(len(actual), rows[0]['size'])
            self.assertEqual((rows[0]['width'], rows[0]['height']), (1, 1))

    def test_all_declared_native_frames_are_emitted_once(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in module.NAMES:
                (root / name).write_bytes(synthetic_png())
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                module.emit(root)
            rows = [json.loads(line.removeprefix('SANJAAL_NATIVE_PIXEL '))
                    for line in out.getvalue().splitlines()
                    if line.startswith('SANJAAL_NATIVE_PIXEL ')]
            self.assertEqual([row['name'] for row in rows], list(module.NAMES))
            self.assertEqual(len(module.NAMES), len(set(module.NAMES)))

    def test_total_bound_remains_enforced(self):
        with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()):
            root = Path(folder)
            data = synthetic_png(module.MAX_TOTAL // len(module.NAMES) + 100)
            for name in module.NAMES:
                (root / name).write_bytes(data)
            with self.assertRaisesRegex(ValueError, 'bound'):
                module.emit(root)

    def test_every_journey_boundary_is_declared(self):
        import re
        root = Path(__file__).resolve().parents[2] / 'app/integration_test'
        expected = set()
        for filename in ['ios_flows_test.dart', 'native_first_use_journey.dart', 'native_group_journey.dart', 'native_report_restart.dart', 'native_chat_text_restart.dart']:
            for name in re.findall(r"(?:capture|picture)\('([^']+)'\)", (root / filename).read_text()):
                if '${' not in name and name != 'ios_test_teardown':
                    expected.add('native_' + name + '.png')
        expected.update('native_ios_tab_' + tab + '.png' for tab in ['reels', 'chats', 'wallet', 'me', 'home'])
        expected.add('ios-diagnostic-native.png')
        self.assertEqual(set(module.NAMES), expected)

    def test_device_access_alone_is_not_complete_native_coverage(self):
        with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()):
            root = Path(folder)
            (root / 'native_ios_native_device_access.png').write_bytes(synthetic_png())
            with self.assertRaisesRegex(ValueError, 'Required'):
                module.emit(root)

    def test_failed_run_partial_diagnostics_are_explicit(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'native_ios_first_use_intro.png').write_bytes(synthetic_png())
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                module.emit(root, require_complete=False)
            self.assertIn('failed-run partial diagnostics', out.getvalue())
            self.assertIn('Missing declared native frames', out.getvalue())

    def test_failed_run_prefers_pre_exit_teardown_frame(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            expected = synthetic_png(7)
            (root / 'ios-diagnostic-native.png').write_bytes(synthetic_png(1))
            (root / 'native_ios_test_teardown.png').write_bytes(expected)
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                module.emit(root, require_complete=False)
            rows = [json.loads(line.removeprefix('SANJAAL_NATIVE_PIXEL ')) for line in out.getvalue().splitlines() if line.startswith('SANJAAL_NATIVE_PIXEL ')]
            self.assertEqual(rows[0]['name'], 'ios-diagnostic-native.png')
            self.assertEqual(base64.b64decode(rows[0]['png']), expected)
            self.assertIn('Native diagnostic source: native_ios_test_teardown.png', out.getvalue())
    def test_success_keeps_declared_host_frame(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            expected = synthetic_png(3)
            for name in module.NAMES:
                (root / name).write_bytes(expected)
            (root / 'native_ios_test_teardown.png').write_bytes(synthetic_png(9))
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                module.emit(root)
            rows = [json.loads(line.removeprefix('SANJAAL_NATIVE_PIXEL ')) for line in out.getvalue().splitlines() if line.startswith('SANJAAL_NATIVE_PIXEL ')]
            self.assertEqual(base64.b64decode(rows[-1]['png']), expected)
    def test_teardown_symlink_is_not_an_evidence_input(self):
        with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()):
            root = Path(folder)
            (root / 'fixture.png').write_bytes(synthetic_png())
            (root / 'native_ios_test_teardown.png').symlink_to(root / 'fixture.png')
            with self.assertRaisesRegex(ValueError, 'regular'):
                module.emit(root, require_complete=False)
    def test_missing_required_capture_fails(self):
        with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(ValueError, 'Required'):
                module.emit(Path(folder))

    def test_oversized_capture_fails_before_reading(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with (root / 'native_ios_native_device_access.png').open('wb') as file:
                file.truncate(module.MAX_IMAGE + 1)
            with self.assertRaisesRegex(ValueError, 'bound'):
                module.emit(root)

    def test_symlink_is_not_an_evidence_input(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'fixture.png').write_bytes(synthetic_png())
            (root / 'native_ios_native_device_access.png').symlink_to(root / 'fixture.png')
            with self.assertRaisesRegex(ValueError, 'regular'):
                module.emit(root)


if __name__ == '__main__':
    unittest.main()
