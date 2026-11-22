#!/usr/bin/env python3
"""Fail closed before API image publication when reviewed source differs.

This is a source/payload check, never deployment permission. A future deliberate
change to the guarded file needs review and an updated pin, not a skipped check.
"""
from pathlib import Path
import argparse, gzip, hashlib, io, json, tarfile
REVIEWED_GUARD_SHA256 = 'e45bf0774d525aa50f4e9bee957c8f679f767a06ffe6ad7cc39c3b3b4c885b0b'
REVIEWED_IMAGE = 'sha256:5f9cdf147ee367b8257833734b6f4f5ebfa2b04d02f4e8f48a0e17cbf4a60ad3'
GUARD = Path('app/Auth/Auth0Guard.php')

def require(value, message):
    if not value:
        raise ValueError('API security floor: ' + message)

def check_content(content):
    digest = hashlib.sha256(content).hexdigest()
    require(digest == REVIEWED_GUARD_SHA256, 'guard differs from reviewed source; review and pin update required')
    return digest

def check_api_root(root):
    root = Path(root).resolve()
    path = root / GUARD
    require(path.is_file() and not path.is_symlink(), 'guard must be a regular file')
    require(path.resolve().is_relative_to(root), 'guard escapes API root')
    require(path.stat().st_size <= 32 * 1024, 'guard exceeds review limit')
    return check_content(path.read_bytes())

def check_prepared_root(root):
    return check_api_root(Path(root) / 'app')

def check_app_layer(compressed):
    require(len(compressed) <= 256 * 1024 * 1024, 'compressed layer exceeds audit limit')
    seen = 0
    total = 0
    count = 0
    target = 'app/' + GUARD.as_posix()
    parents = {'app', 'app/app', 'app/app/Auth'}
    with gzip.GzipFile(fileobj=io.BytesIO(compressed)) as stream:
        with tarfile.open(fileobj=stream, mode='r|') as tar:
            for member in tar:
                count += 1
                total += max(0, member.size)
                require(count <= 100000 and total <= 256 * 1024 * 1024, 'expanded layer exceeds audit limit')
                name = member.name.rstrip('/')
                require(not name.startswith('/') and '..' not in Path(name).parts and Path(name).as_posix() == name, 'unsafe layer member')
                if name in parents:
                    require(member.isdir(), 'guard ancestor is not a directory')
                if name == target:
                    seen += 1
                    require(seen == 1 and member.isfile() and member.size <= 32 * 1024, 'guard member missing, duplicate or not regular')
                    check_content(tar.extractfile(member).read())
    require(seen == 1, 'guard missing from exact image payload')
    return REVIEWED_GUARD_SHA256

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    group = p.add_mutually_exclusive_group(required=True)
    group.add_argument('--api-root')
    group.add_argument('--prepared-root')
    args = p.parse_args()
    digest = check_api_root(args.api_root) if args.api_root else check_prepared_root(args.prepared_root)
    print(json.dumps({'security_floor_passed': True, 'guard_sha256': digest, 'deployment_allowed': False}))
