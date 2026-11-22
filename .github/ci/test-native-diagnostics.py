"""Diagnostic extraction tests use synthetic noise, never device evidence."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('diagnostics',Path(__file__).with_name('native-diagnostics.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class NativeDiagnosticsTest(unittest.TestCase):
    def test_keeps_failure_context_before_large_system_tail(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'driver.log'
            path.write_text('startup\n'+'routine line\n'*300+'TestFailure: synthetic route transition\nExpected: one\nActual: three\n'+'OS status noise\n'*20000)
            value=module.excerpt(path)
            self.assertIn('synthetic route transition',value)
            self.assertIn('Actual: three',value)
            self.assertIn('startup',value)
            self.assertLessEqual(len(value.encode()),module.MAX_OUTPUT+100)
    def test_output_has_a_byte_bound_with_many_error_lines(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'driver.log';path.write_text(('Error: '+'文'*3000+'\n')*900)
            self.assertLessEqual(len(module.excerpt(path).encode()),module.MAX_OUTPUT+100)
    def test_os_error_noise_cannot_evict_real_failure_or_tail(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'driver.log'
            noise=('OS Error: assertion acquisition failed '+'.'*300+'\n')
            path.write_text('startup sentinel\n'+noise*7000+'TestFailure: real fixture result\nExpected: one member\nActual: no members\n'+noise*500+'final sentinel\n')
            value=module.excerpt(path)
            for signal in ['startup sentinel','real fixture result','Expected: one member','Actual: no members','final sentinel']:
                self.assertIn(signal,value)
            self.assertLessEqual(len(value.encode()),module.MAX_OUTPUT)
    def test_repeated_test_signals_cannot_evict_latest_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'driver.log'
            path.write_text('startup sentinel\n'+('TestFailure: earlier synthetic noise '+'.'*200+'\n')*15000+'TestFailure: latest specific result\nActual: latest specific state\nfinal sentinel\n')
            value=module.excerpt(path)
            self.assertIn('latest specific result',value)
            self.assertIn('latest specific state',value)
            self.assertIn('final sentinel',value)
            self.assertLessEqual(len(value.encode()),module.MAX_OUTPUT)
    def test_symlink_is_not_read(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'link';(Path(folder)/'source').write_text('not allowed');path.symlink_to(Path(folder)/'source')
            self.assertNotIn('not allowed',module.excerpt(path))
    def test_missing_file_is_explicit(self):
        self.assertIn('not present',module.excerpt(Path('/not-a-native-diagnostic-file')))
    def test_oversized_file_reads_bounded_head_and_tail(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'driver.log'
            with path.open('wb') as file:
                file.write(b'initial\n');file.seek(module.MAX_INPUT*2);file.write(b'\nError: final synthetic cause\n')
            value=module.excerpt(path)
            self.assertIn('initial',value);self.assertIn('final synthetic cause',value)
            self.assertLessEqual(len(value.encode()),module.MAX_OUTPUT+100)

if __name__=='__main__':unittest.main()
