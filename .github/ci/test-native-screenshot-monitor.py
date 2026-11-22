import importlib.util
from pathlib import Path
import subprocess
import sys
import time
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
            return subprocess.CompletedProcess(args, 0, stdout=str(self.container))
        def capture(device, target):
            self.assertEqual(device, 'synthetic-device')
            target.write_bytes(PNG)
        with mock.patch.object(module.subprocess, 'run', side_effect=run) as called, mock.patch.object(module, 'capture_with_retries', side_effect=capture) as captured:
            monitor = module.simulator_monitor('synthetic-device', self.output)
            self.request()
            monitor.scan()
            self.request('2-ios_test')
            monitor.scan()
            self.assertEqual(called.call_count, 1)
            self.assertEqual(captured.call_count, 2)

    def test_transient_capture_timeout_retries_fresh_then_acknowledges_once(self):
        pending = self.request()
        attempts = []
        def capture(args):
            target = Path(args[-1]); attempts.append(target)
            self.assertEqual(args[:5], ['xcrun', 'simctl', 'io', 'synthetic-device', 'screenshot'])
            if len(attempts) == 1:
                target.write_bytes(PNG + b'partial')
                raise subprocess.TimeoutExpired(args, module.CAPTURE_TIMEOUT)
            self.assertFalse(attempts[0].exists())
            self.assertNotEqual(attempts[0], target)
            target.write_bytes(PNG)
        self.monitor.capture = lambda target: module.capture_with_retries('synthetic-device', target)
        with mock.patch.object(module, 'run_native_capture', side_effect=capture):
            self.monitor.scan(); self.monitor.scan()
        self.assertEqual(len(attempts), 2)
        self.assertEqual(pending.with_suffix('.native-done').read_text(), '1-ios_test')
        self.assertEqual((self.output / 'native_ios_test.png').read_bytes(), PNG)
        self.assertFalse(list(self.output.glob('.*.attempt*.png')))

    def test_permanent_timeouts_never_acknowledge_or_leave_partial_images(self):
        pending = self.request()
        def capture(args):
            Path(args[-1]).write_bytes(PNG)
            raise subprocess.TimeoutExpired(args, module.CAPTURE_TIMEOUT)
        self.monitor.capture = lambda target: module.capture_with_retries('synthetic-device', target)
        with mock.patch.object(module, 'run_native_capture', side_effect=capture) as called:
            with self.assertRaises(subprocess.TimeoutExpired): self.monitor.scan()
        self.assertEqual(called.call_count, module.CAPTURE_ATTEMPTS)
        self.assertFalse(pending.with_suffix('.native-done').exists())
        self.assertFalse(self.monitor.seen)
        self.assertFalse(list(self.output.iterdir()))

    def test_non_timeout_failure_is_not_retried(self):
        self.request()
        self.monitor.capture = lambda target: module.capture_with_retries('synthetic-device', target)
        with mock.patch.object(module, 'run_native_capture', side_effect=subprocess.CalledProcessError(1, ['synthetic'])) as called:
            with self.assertRaises(subprocess.CalledProcessError): self.monitor.scan()
        self.assertEqual(called.call_count, 1)

    def test_retry_still_cannot_acknowledge_a_changed_request(self):
        pending = self.request()
        attempts = 0
        def capture(args):
            nonlocal attempts
            attempts += 1
            if attempts == 1: raise subprocess.TimeoutExpired(args, module.CAPTURE_TIMEOUT)
            Path(args[-1]).write_bytes(PNG)
            pending.write_text('2-ios_test')
        self.monitor.capture = lambda target: module.capture_with_retries('synthetic-device', target)
        with mock.patch.object(module, 'run_native_capture', side_effect=capture):
            with self.assertRaises(ValueError): self.monitor.scan()
        self.assertFalse(pending.with_suffix('.native-done').exists())
        self.assertFalse(self.monitor.seen)

    def test_attempt_budget_leaves_at_least_ten_seconds_for_ack(self):
        self.assertLessEqual(module.CAPTURE_ATTEMPTS * (module.CAPTURE_TIMEOUT + module.CAPTURE_REAP_TIMEOUT), 50)

    def test_timeout_kills_and_reaps_own_process_group_before_retry(self):
        child = mock.Mock(pid=123456)
        child.wait.side_effect = [subprocess.TimeoutExpired(['synthetic'], 20), 0]
        with mock.patch.object(module.subprocess, 'Popen', return_value=child) as launched, mock.patch.object(module.os, 'killpg') as killed:
            with self.assertRaises(subprocess.TimeoutExpired): module.run_native_capture(['synthetic'])
        launched.assert_called_once_with(['synthetic'], start_new_session=True)
        killed.assert_called_once_with(child.pid, module.signal.SIGKILL)
        self.assertEqual(child.wait.call_args_list, [mock.call(timeout=module.CAPTURE_TIMEOUT), mock.call(timeout=module.CAPTURE_REAP_TIMEOUT)])

    def test_unreaped_attempt_is_terminal_not_a_second_writer(self):
        child = mock.Mock(pid=123456)
        child.wait.side_effect = subprocess.TimeoutExpired(['synthetic'], 20)
        with mock.patch.object(module.subprocess, 'Popen', return_value=child), mock.patch.object(module.os, 'killpg'):
            with self.assertRaisesRegex(RuntimeError, 'could not be reaped'): module.run_native_capture(['synthetic'])

    def test_real_timed_out_process_group_cannot_write_a_late_image(self):
        late = self.root / 'late-image.png'
        worker = "import pathlib,sys,time;time.sleep(0.4);pathlib.Path(sys.argv[1]).write_bytes(b'late')"
        parent = "import subprocess,sys,time;subprocess.Popen([sys.executable,'-c',sys.argv[1],sys.argv[2]]);print('ready',flush=True);time.sleep(3)"
        real_popen = subprocess.Popen
        created = []
        def launch(args, **kwargs):
            child = real_popen(args, stdout=subprocess.PIPE, **kwargs)
            created.append(child)
            self.assertEqual(child.stdout.readline(), b'ready\n')
            return child
        try:
            with mock.patch.object(module.subprocess, 'Popen', side_effect=launch), mock.patch.object(module, 'CAPTURE_TIMEOUT', 0.05):
                with self.assertRaises(subprocess.TimeoutExpired):
                    module.run_native_capture([sys.executable, '-c', parent, worker, str(late)])
            self.assertIsNotNone(created[0].poll())
            time.sleep(0.5)
            self.assertFalse(late.exists())
        finally:
            for child in created:
                if child.poll() is None:
                    module.os.killpg(child.pid, module.signal.SIGKILL)
                    child.wait(timeout=3)
                child.stdout.close()

    def test_attempt_symlink_is_rejected_without_touching_foreign_file(self):
        self.output.mkdir()
        outside = self.root / 'outside'
        outside.write_bytes(b'keep')
        temporary = self.output / '.native_ios_test.attempt1.png'
        temporary.symlink_to(outside)
        with mock.patch.object(module, 'run_native_capture') as run:
            with self.assertRaises(ValueError): module.capture_with_retries('synthetic', self.output / 'native_ios_test.png')
        run.assert_not_called()
        self.assertEqual(outside.read_bytes(), b'keep')

    def test_nonzero_capture_process_exit_is_propagated(self):
        child = mock.Mock()
        child.wait.return_value = 1
        with mock.patch.object(module.subprocess, 'Popen', return_value=child):
            with self.assertRaises(subprocess.CalledProcessError): module.run_native_capture(['synthetic'])

    def test_retry_budget_matches_actual_app_acknowledgement_deadline(self):
        source = (Path(__file__).resolve().parents[2] / 'app/integration_test/ios_flows_test.dart').read_text()
        callback = source.split('acknowledge: () async {', 1)[1].split('return false', 1)[0]
        match = module.re.search(r'Duration\(\s*seconds:\s*(\d+)\s*\)', callback)
        self.assertIsNotNone(match)
        budget = module.CAPTURE_ATTEMPTS * (module.CAPTURE_TIMEOUT + module.CAPTURE_REAP_TIMEOUT)
        self.assertLessEqual(budget + 10, int(match.group(1)))


if __name__ == '__main__':
    unittest.main()
