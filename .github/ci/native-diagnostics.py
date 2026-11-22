"""Bounded synthetic-job diagnostics. No artifact storage or production inputs."""
from pathlib import Path
import re
import sys

MAX_INPUT = 4 * 1024 * 1024
MAX_OUTPUT = 192 * 1024
# OS logs contain thousands of unrelated Error:/assertion messages. Keep actual
# test signals distinct, and reserve space for the end even if matches are noisy.
PATTERN = re.compile(
    r'EXCEPTION CAUGHT|TestFailure|Some tests failed|NoSuchMethodError|'
    r'The following .{0,120}(?:was thrown|assertion)|'
    r'(?:^|\s)(?:Expected:|Actual:|#0\s)|'
    r'Lost connection to device|native journey failure'
)
NAMES = ('ios-driver-seed.log', 'ios-driver-recover.log', 'build/screenshots/report-process-identity.json', 'ios-driver-exit.txt', 'ios-driver-output.log', 'ios-native-console.log',
         'ios-build.log', 'build/screenshots/ios-stages.log')


def bounded_section(label, indexed_lines, budget):
    result = [label]
    remaining = budget - len(label.encode()) - 1
    for number, text in indexed_lines:
        line = f'{number}: {text[:2048]}'
        data = line.encode()
        if len(data) + 1 > remaining:
            result.append('[section byte bound reached]')
            break
        result.append(line)
        remaining -= len(data) + 1
    return '\n'.join(result)


def excerpt(path):
    if path.is_symlink() or not path.is_file():
        return '[not present as a regular file]'
    with path.open('rb') as file:
        data = file.read(MAX_INPUT + 1)
    prefix = ''
    if len(data) > MAX_INPUT:
        prefix = '[Input is bounded to first and last byte windows. Numbers below address the combined excerpt, not original file lines.]\n'
        with path.open('rb') as file:
            file.seek(-MAX_INPUT // 2, 2)
            tail = file.read(MAX_INPUT // 2)
        data = data[:MAX_INPUT // 2] + b'\n[omitted middle of oversized input]\n' + tail
    text = data.decode('utf-8', errors='replace')
    if len(text.encode()) <= MAX_OUTPUT:
        return prefix + '\n'.join(line[:2048] for line in text.splitlines())
    lines = text.splitlines()
    head_end = min(40, len(lines))
    tail_start = max(head_end, len(lines) - 80)
    picks = set()
    for i, line in enumerate(lines):
        if PATTERN.search(line):
            picks.update(range(max(head_end, i - 4), min(tail_start, i + 15)))
    numbered = lambda indices: ((i + 1, lines[i]) for i in indices)
    # Keep both ends of a very noisy matching region. A later test failure must
    # not disappear merely because earlier framework errors filled the budget.
    ordered = sorted(picks)
    split = len(ordered) // 2
    sections = [
        bounded_section('[head]', numbered(range(head_end)), 16 * 1024),
        bounded_section('[first test context]', numbered(ordered[:split]), 64 * 1024),
        bounded_section('[last test context, newest first]', numbered(reversed(ordered[split:])), 64 * 1024),
        bounded_section('[tail, newest first]', numbered(range(len(lines)-1, tail_start-1, -1)), 40 * 1024),
    ]
    return prefix + '\n'.join(sections)


def emit(root):
    for name in NAMES:
        print('SYNTHETIC NATIVE DIAGNOSTIC ' + name, flush=True)
        print(excerpt(root / name), flush=True)


if __name__ == '__main__':
    emit(Path(sys.argv[1]) if len(sys.argv) > 1 else Path('app'))
