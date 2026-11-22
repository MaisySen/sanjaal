"""Synthetic host-driver checks only, no simulator proof."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).parent


class DriverTest(unittest.TestCase):
    def load(self):
        with patch.dict(os.environ, {'IOS_DEVICE': 'synthetic-device'}):
            spec = importlib.util.spec_from_file_location('report_driver', ROOT / 'native-report-restart-driver.py')
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module

    def exercise(self, *, driver_code=0, duplicate=False, monitor_error=False):
        m = self.load()
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            (base / 'Library/Application Support').mkdir(parents=True)
            m.ROOT = base / 'output'
            m.ROOT.mkdir()
            commands, killed, waits = [], [], []
            monitor = types.SimpleNamespace(scan=lambda: None)
            native_module = types.SimpleNamespace(simulator_monitor=lambda *a: monitor)
            def execute(command, **kwargs):
                commands.append(command)
                if 'get_app_container' in command:
                    return str(base if command[-1] == 'data' else base / 'app')
                return 'au.fintex.sanjaal: ' + str(101 if duplicate else 101 + sum('launch' in c for c in commands))
            class Response:
                def __enter__(self): return self
                def __exit__(self, *args): pass
                def read(self): return json.dumps({'result': {'type': 'VM'}})
            class Child:
                def wait(self, **kwargs): return driver_code
            class Thread:
                def __init__(self, *args, **kwargs): pass
                def start(self): pass
                def join(self, **kwargs): pass
                def is_alive(self): return monitor_error
            with patch.object(m.subprocess, 'check_output', side_effect=execute), \
                 patch.object(m.subprocess, 'run', side_effect=lambda *a, **k: commands.append(a[0])), \
                 patch.object(m.subprocess, 'Popen', return_value=Child()), \
                 patch.object(m.os, 'kill', side_effect=lambda pid, signal: killed.append(pid)), \
                 patch.object(m, 'wait_absent', side_effect=lambda pid: waits.append(pid)), \
                 patch.object(m.urllib.request, 'urlopen', return_value=Response()), \
                 patch.object(m.importlib.util, 'spec_from_file_location', return_value=types.SimpleNamespace(loader=types.SimpleNamespace(exec_module=lambda x: None))), \
                 patch.object(m.importlib.util, 'module_from_spec', return_value=native_module), \
                 patch.object(m.threading, 'Thread', Thread):
                m.main()
            result = json.loads((m.ROOT / 'report-process-identity.json').read_text())
            self.assertEqual(result['installations'], 1)
            self.assertEqual(len(set(result['process_ids'])), 2)
            self.assertEqual(len(waits), 2)
            self.assertEqual(sum('terminate' in command for command in commands), 2)
            self.assertFalse(any('install' in command or 'uninstall' in command or 'erase' in command for command in commands))
            self.assertTrue((base / 'Library/Application Support/report-restart-recover').exists())

    def test_same_installed_app_two_processes(self):
        self.exercise()

    def test_driver_failure_stops_before_recovery(self):
        with self.assertRaisesRegex(AssertionError, 'driver failed'):
            self.exercise(driver_code=1)

    def test_duplicate_process_is_rejected(self):
        with self.assertRaises(AssertionError):
            self.exercise(duplicate=True)

    def test_monitor_failure_rejects_run(self):
        with self.assertRaises(AssertionError):
            self.exercise(monitor_error=True)


if __name__ == '__main__':
    unittest.main()
