import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('monitor', Path(__file__).with_name('native-screenshot-monitor.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
PNG = b'\x89PNG\r\n\x1a\n' + b'0' * 32


class MonitorTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.container = self.root / 'container'
        self.folder = self.container / 'Library/Caches/ios-evidence'
        self.folder.mkdir(parents=True)
        self.output = self.root / 'output'
        self.calls = []
        self.monitor = module.NativeScreenshotMonitor(self.container, self.output, self.capture)

    def capture(self, target):
        self.calls.append(target)
        target.write_bytes(PNG)

    def request(self, value='1-ios_test', name='ios_test'):
        path = self.folder / (name + '.native-pending')
        path.write_text(value)
        return path

    def test_fresh_acknowledgement_and_once_only_same_request(self):
        pending = self.request()
        self.monitor.scan()
        self.monitor.scan()
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(pending.with_suffix('.native-done').read_text(), '1-ios_test')

    def test_new_request_of_same_name_is_captured_again(self):
        pending = self.request()
        self.monitor.scan()
        pending.write_text('2-ios_test')
        self.monitor.scan()
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(pending.with_suffix('.native-done').read_text(), '2-ios_test')

    def test_stale_acknowledgement_is_replaced_by_current_request(self):
        pending = self.request()
        pending.with_suffix('.native-done').write_text('old')
        self.monitor.scan()
        self.assertEqual(pending.with_suffix('.native-done').read_text(), '1-ios_test')

    def test_failed_capture_cannot_acknowledge(self):
        pending = self.request()
        self.monitor.capture = mock.Mock(side_effect=subprocess.TimeoutExpired('synthetic', 45))
        with self.assertRaises(subprocess.TimeoutExpired):
            self.monitor.scan()
        self.assertFalse(pending.with_suffix('.native-done').exists())
        self.assertFalse(self.monitor.seen)

    def test_old_image_cannot_count_as_a_new_capture(self):
        pending = self.request()
        self.output.mkdir()
        (self.output / 'native_ios_test.png').write_bytes(PNG)
        self.monitor.capture = lambda target: None
        with self.assertRaises(ValueError):
            self.monitor.scan()
        self.assertFalse(pending.with_suffix('.native-done').exists())

    def test_changed_request_during_capture_cannot_acknowledge(self):
        pending = self.request()
        def capture(target):
            target.write_bytes(PNG)
            pending.write_text('2-ios_test')
        self.monitor.capture = capture
        with self.assertRaises(ValueError):
            self.monitor.scan()
        self.assertFalse(pending.with_suffix('.native-done').exists())

    def test_empty_request_retries_without_acknowledgement(self):
        pending = self.request('')
        self.monitor.scan()
        self.assertFalse(pending.with_suffix('.native-done').exists())
        pending.write_text('1-ios_test')
        self.monitor.scan()
        self.assertEqual(len(self.calls), 1)

    def test_bad_name_and_foreign_request_are_rejected(self):
        pending = self.request('1-ios_other')
        with self.assertRaises(ValueError):
            self.monitor.scan()
        pending.unlink()
        self.request('1-foreign', 'foreign')
        with self.assertRaises(ValueError):
            self.monitor.scan()
        self.assertFalse(self.calls)

    def test_symlink_request_and_image_cannot_write_outside_evidence(self):
        outside = self.root / 'outside'
        outside.write_text('1-ios_test')
        pending = self.folder / 'ios_test.native-pending'
        pending.symlink_to(outside)
        with self.assertRaises(ValueError):
            self.monitor.scan()
        pending.unlink()
        self.request()
        self.output.mkdir()
        (self.output / 'native_ios_test.png').symlink_to(outside)
        with self.assertRaises(ValueError):
            self.monitor.scan()
        self.assertEqual(outside.read_text(), '1-ios_test')

    def test_evidence_directories_are_cached_after_discovery(self):
        self.request()
        self.monitor.scan()
        with mock.patch.object(Path, 'rglob', side_effect=AssertionError('Repeated recursive discovery')):
            self.monitor.scan()

    def test_container_discovery_happens_once_and_commands_have_timeouts(self):
        def run(args, **kwargs):
            self.assertIn('timeout', kwargs)
            if 'get_app_container' in args:
                return subprocess.CompletedProcess(args, 0, stdout=str(self.container))
            Path(args[-1]).write_bytes(PNG)
            return subprocess.CompletedProcess(args, 0)
        with mock.patch.object(module.subprocess, 'run', side_effect=run) as called:
            monitor = module.simulator_monitor('synthetic-device', self.output)
            self.request()
            monitor.scan()
            self.request('2-ios_test')
            monitor.scan()
            self.assertEqual(called.call_count, 3)


if __name__ == '__main__':
    unittest.main()
