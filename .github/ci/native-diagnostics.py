"""Bounded synthetic-job diagnostics. No artifact storage or production inputs."""
from pathlib import Path
import re
import sys

MAX_INPUT = 4 * 1024 * 1024
MAX_OUTPUT = 192 * 1024
PATTERN = re.compile(r'EXCEPTION CAUGHT|TestFailure|test failed|Error:|Expected:|Actual:|NoSuchMethodError|The following|Lost connection|Some tests failed|Assertion|#0\s', re.I)
NAMES = ('ios-driver-exit.txt', 'ios-driver-output.log', 'ios-native-console.log',
         'ios-build.log', 'build/screenshots/ios-stages.log')


def excerpt(path):
    if path.is_symlink() or not path.is_file():
        return '[not present as a regular file]'
    with path.open('rb') as file:
        data = file.read(MAX_INPUT + 1)
    if len(data) > MAX_INPUT:
        with path.open('rb') as file:
            file.seek(-MAX_INPUT // 2, 2)
            tail = file.read(MAX_INPUT // 2)
        data = data[:MAX_INPUT // 2] + b'\n[omitted middle of oversized input]\n' + tail
    text = data.decode('utf-8', errors='replace')
    if len(text.encode()) <= MAX_OUTPUT:
        return '\n'.join(line[:2048] for line in text.splitlines())
    lines = text.splitlines()
    picks = set(range(min(40, len(lines)))) | set(range(max(0, len(lines)-40), len(lines)))
    for i, line in enumerate(lines):
        if PATTERN.search(line):
            picks.update(range(max(0, i-4), min(len(lines), i+15)))
    result=[]
    budget=MAX_OUTPUT
    for i in sorted(picks):
        line=f'{i+1}: {lines[i][:2048]}'
        size=len(line.encode())+1
        if size>budget:
            result.append('[diagnostic output bound reached]');break
        result.append(line);budget-=size
    return '\n'.join(result)


def emit(root):
    for name in NAMES:
        print('SYNTHETIC NATIVE DIAGNOSTIC '+name, flush=True)
        print(excerpt(root/name), flush=True)


if __name__=='__main__':
    emit(Path(sys.argv[1]) if len(sys.argv)>1 else Path('app'))
