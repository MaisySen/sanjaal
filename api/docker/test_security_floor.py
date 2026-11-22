#!/usr/bin/env python3
import gzip, io, os, subprocess, sys, tarfile, tempfile, unittest
from pathlib import Path
import security_floor as floor
HERE = Path(__file__).resolve().parent
GUARD = (HERE.parent / floor.GUARD).read_bytes()

class SecurityFloorTests(unittest.TestCase):
    def archive(self, members):
        stream = io.BytesIO()
        with tarfile.open(fileobj=stream, mode='w') as tar:
            for name, content, kind in members:
                member = tarfile.TarInfo(name)
                if kind == 'file':
                    member.size = len(content)
                    tar.addfile(member, io.BytesIO(content))
                else:
                    member.type = tarfile.SYMTYPE
                    member.linkname = 'elsewhere'
                    tar.addfile(member)
        return gzip.compress(stream.getvalue(), mtime=0)

    def test_source_passes_current_reviewed_pin(self):
        self.assertEqual(floor.check_api_root(HERE.parent), floor.REVIEWED_GUARD_SHA256)

    def test_different_content_is_rejected(self):
        with self.assertRaises(ValueError): floor.check_content(GUARD + b' ')

    def test_missing_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(ValueError): floor.check_api_root(root)

    def test_symlink_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / floor.GUARD
            path.parent.mkdir(parents=True)
            path.symlink_to(HERE.parent / floor.GUARD)
            with self.assertRaises(ValueError): floor.check_api_root(root)

    def test_oversized_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / floor.GUARD
            path.parent.mkdir(parents=True)
            path.write_bytes(b' ' * (32 * 1024 + 1))
            with self.assertRaises(ValueError): floor.check_api_root(root)

    def test_prepared_root_is_checked_not_repository_copy(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'app' / floor.GUARD
            path.parent.mkdir(parents=True)
            path.write_bytes(GUARD)
            self.assertEqual(floor.check_prepared_root(root), floor.REVIEWED_GUARD_SHA256)
            path.write_bytes(b'different prepared payload')
            with self.assertRaises(ValueError): floor.check_prepared_root(root)

    def test_exact_serialized_payload_passes(self):
        self.assertEqual(floor.check_app_layer(self.archive([('app/' + floor.GUARD.as_posix(), GUARD, 'file')])), floor.REVIEWED_GUARD_SHA256)

    def test_missing_payload_member_is_rejected(self):
        with self.assertRaises(ValueError): floor.check_app_layer(self.archive([('app/other', b'', 'file')]))

    def test_changed_payload_member_is_rejected(self):
        with self.assertRaises(ValueError): floor.check_app_layer(self.archive([('app/' + floor.GUARD.as_posix(), b'changed', 'file')]))

    def test_duplicate_payload_member_is_rejected(self):
        member = ('app/' + floor.GUARD.as_posix(), GUARD, 'file')
        with self.assertRaises(ValueError): floor.check_app_layer(self.archive([member, member]))

    def test_path_alias_is_rejected(self):
        member = ('app/' + floor.GUARD.as_posix(), GUARD, 'file')
        with self.assertRaises(ValueError): floor.check_app_layer(self.archive([member, ('./' + member[0], b'changed', 'file')]))

    def test_payload_symlink_is_rejected(self):
        with self.assertRaises(ValueError): floor.check_app_layer(self.archive([('app/' + floor.GUARD.as_posix(), b'', 'link')]))

    def test_payload_parent_link_is_rejected(self):
        member = ('app/' + floor.GUARD.as_posix(), GUARD, 'file')
        with self.assertRaises(ValueError): floor.check_app_layer(self.archive([('app/app/Auth', b'', 'link'), member]))

    def test_publisher_refuses_before_reading_credentials_or_network(self):
        with tempfile.TemporaryDirectory() as root:
            run = subprocess.run([sys.executable, str(HERE / 'build.py'), 'fixture-not-published'], env={**os.environ, 'SANJAAL_PREPARED_ROOT': root}, capture_output=True, text=True)
            self.assertNotEqual(run.returncode, 0)
            self.assertIn('API security floor:', run.stderr)
            self.assertNotIn('pat.keep', run.stderr)

    def test_gate_runs_before_every_blob_publication(self):
        import ast
        tree = ast.parse((HERE / 'build.py').read_text())
        calls = [(node.lineno, node.func.id) for statement in tree.body for node in ast.walk(statement) if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in {'check_app_layer', 'push_blob'} and not isinstance(statement, (ast.FunctionDef, ast.AsyncFunctionDef))]
        self.assertEqual(sum(name == 'check_app_layer' for _, name in calls), 1)
        check_line = next(line for line, name in calls if name == 'check_app_layer')
        self.assertTrue(all(line > check_line for line, name in calls if name == 'push_blob'))

if __name__ == '__main__': unittest.main()
