"""Local synthetic simulator evidence only. Never used by the shipped app."""
from pathlib import Path
import re
import os
import signal
import subprocess


class NativeScreenshotMonitor:
    def __init__(self, container, output, capture):
        self.container = Path(container)
        self.output = Path(output)
        self.capture = capture
        self.folders = []
        self.seen = set()

    def scan(self):
        # Cache the evidence directories. Repeated simctl container discovery
        # and recursive scans must not delay the next screenshot boundary.
        if not self.folders:
            self.folders = [p for p in self.container.rglob('ios-evidence')
                            if p.is_dir() and not p.is_symlink()]
        for folder in self.folders:
            for pending in sorted(folder.glob('*.native-pending')):
                name = pending.stem
                if not re.fullmatch(r'ios_[a-z0-9_]{1,100}', name):
                    raise ValueError('Unexpected synthetic capture name')
                if pending.is_symlink() or not pending.is_file() or pending.stat().st_size > 256:
                    raise ValueError('Invalid native capture request')
                request = pending.read_text()
                if not re.fullmatch(r'[0-9]{1,30}-' + re.escape(name), request):
                    # An atomicity window during the Dart write can be retried.
                    if not request:
                        continue
                    raise ValueError('Invalid native capture request identity')
                key = (str(pending), request)
                if key in self.seen:
                    continue
                self.output.mkdir(parents=True, exist_ok=True)
                target = self.output / ('native_' + name + '.png')
                if target.is_symlink():
                    raise ValueError('Native image target must not be a symlink')
                if target.exists():
                    if not target.is_file():
                        raise ValueError('Native image target must be a regular file')
                    target.unlink()
                self.capture(target)
                if not target.is_file() or target.is_symlink() or target.stat().st_size < 24:
                    raise ValueError('Native capture did not produce an image')
                # A late result cannot acknowledge a newer request of the same name.
                if pending.read_text() != request:
                    raise ValueError('Native request changed during capture')
                done = pending.with_suffix('.native-done')
                if done.is_symlink():
                    raise ValueError('Native acknowledgement must not be a symlink')
                temp = pending.with_suffix('.native-done-tmp')
                if temp.is_symlink():
                    raise ValueError('Native acknowledgement target must not be a symlink')
                temp.write_text(request)
                temp.replace(done)
                self.seen.add(key)


# Hosted simctl launch can spend over20s before capture begins (e394 logs).
# Two45s attempts, including reaping, fit inside the120s app-side deadline.
# This bounded retry is not proof that the simulator host hang is fixed.
CAPTURE_ATTEMPTS = 2
CAPTURE_TIMEOUT = 45
CAPTURE_REAP_TIMEOUT = 3


def run_native_capture(args):
    child = subprocess.Popen(args, start_new_session=True)
    try:
        code = child.wait(timeout=CAPTURE_TIMEOUT)
    except subprocess.TimeoutExpired:
        # Reap this attempt's process group before another capture can start.
        # Never leave a timed-out writer racing with a later acknowledgement.
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            child.wait(timeout=CAPTURE_REAP_TIMEOUT)
        except subprocess.TimeoutExpired:
            raise RuntimeError('Native capture process could not be reaped') from None
        raise subprocess.TimeoutExpired(args, CAPTURE_TIMEOUT) from None
    if code:
        raise subprocess.CalledProcessError(code, args)


def capture_with_retries(device, target):
    target = Path(target)
    for attempt in range(1, CAPTURE_ATTEMPTS + 1):
        temporary = target.with_name('.' + target.stem + '.attempt' + str(attempt) + '.png')
        if temporary.is_symlink() or (temporary.exists() and not temporary.is_file()):
            raise ValueError('Native attempt target must be a regular file')
        temporary.unlink(missing_ok=True)
        print('Native capture ' + target.name + ' attempt ' + str(attempt) + '/' + str(CAPTURE_ATTEMPTS), flush=True)
        try:
            run_native_capture(['xcrun', 'simctl', 'io', device, 'screenshot', str(temporary)])
            if not temporary.is_file() or temporary.is_symlink() or temporary.stat().st_size < 24:
                raise ValueError('Native capture attempt did not produce an image')
            if target.exists() or target.is_symlink():
                raise ValueError('Native image target changed during capture')
            temporary.replace(target)
            return
        except subprocess.TimeoutExpired:
            print('Native capture ' + target.name + ' timed out on attempt ' + str(attempt), flush=True)
            if attempt == CAPTURE_ATTEMPTS:
                raise
        finally:
            if temporary.is_symlink() or (temporary.exists() and not temporary.is_file()):
                raise ValueError('Native attempt target changed during capture')
            temporary.unlink(missing_ok=True)


def simulator_monitor(device, output):
    result = subprocess.run(
        ['xcrun', 'simctl', 'get_app_container', device, 'au.fintex.sanjaal', 'data'],
        capture_output=True, text=True, check=True, timeout=15)
    container = Path(result.stdout.strip())
    if not container.is_absolute() or not container.is_dir():
        raise ValueError('Simulator data container is unavailable')

    def capture(target):
        capture_with_retries(device, target)
    return NativeScreenshotMonitor(container, output, capture)
