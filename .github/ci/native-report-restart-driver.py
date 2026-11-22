"""Same installed synthetic candidate, two verified simulator app processes."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import threading
import time
import urllib.request

DEVICE = os.environ['IOS_DEVICE']
BUNDLE = 'au.fintex.sanjaal'
ENDPOINT = 'http://127.0.0.1:57321/'
ROOT = Path('build/screenshots')
ROOT.mkdir(parents=True, exist_ok=True)


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def location(kind):
    return subprocess.check_output(['xcrun', 'simctl', 'get_app_container', DEVICE, BUNDLE, kind], text=True).strip()


def wait_absent(pid):
    deadline = time.monotonic() + 10
    while True:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        if time.monotonic() > deadline:
            raise RuntimeError('Previous simulator process still exists')
        time.sleep(.1)


def main():
    data, app = location('data'), location('app')
    spec = importlib.util.spec_from_file_location('native_monitor', '../.github/ci/native-screenshot-monitor.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    evidence = module.simulator_monitor(DEVICE, ROOT)
    pids = []
    for phase in ['seed', 'recover']:
        assert location('data') == data and location('app') == app
        if phase == 'recover':
            marker = Path(data) / 'Library' / 'Application Support' / 'report-restart-recover'
            assert marker.parent.is_dir()
            marker.write_text('recover')
        launched = subprocess.check_output(['xcrun', 'simctl', 'launch', DEVICE, BUNDLE,
            '--vm-service-host=127.0.0.1', '--vm-service-port=57321', '--disable-service-auth-codes'], text=True)
        pid = int(launched.strip().split(':')[-1])
        assert pid not in pids
        os.kill(pid, 0)
        pids.append(pid)
        (ROOT / ('report-launch-' + phase + '.log')).write_text(launched)
        stop = threading.Event()
        errors = []
        monitor = None
        try:
            deadline = time.monotonic() + 90
            while True:
                try:
                    with urllib.request.urlopen(ENDPOINT + 'getVM', timeout=2) as response:
                        state = json.load(response)
                    assert state['result']['type'] == 'VM'
                    break
                except Exception:
                    if time.monotonic() > deadline:
                        raise
                    time.sleep(1)

            def collect():
                try:
                    while not stop.wait(.2):
                        evidence.scan()
                except Exception as error:
                    errors.append(type(error).__name__)

            monitor = threading.Thread(target=collect, daemon=True)
            monitor.start()
            with open('ios-driver-' + phase + '.log', 'w') as output:
                child = subprocess.Popen(['flutter', 'drive', '-d', DEVICE,
                    '--driver=test_driver/integration_test.dart', '--use-existing-app=' + ENDPOINT,
                    '--no-pub'], stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    code = child.wait(timeout=600)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait(timeout=15)
                    raise
            assert code == 0, 'Native driver failed in ' + phase
            assert not errors, errors
        finally:
            stop.set()
            try:
                if monitor:
                    monitor.join(timeout=50)
                    assert not monitor.is_alive()
            finally:
                run('xcrun', 'simctl', 'terminate', DEVICE, BUNDLE)
                wait_absent(pid)
        print('Verified terminated ' + phase + ' PID ' + str(pid), flush=True)
    assert len(set(pids)) == 2
    assert location('data') == data and location('app') == app
    (ROOT / 'report-process-identity.json').write_text(json.dumps({
        'process_ids': pids, 'same_data_container': True, 'same_installed_app': True,
        'installations': 1, 'phases': ['seed', 'recover']}, indent=2))
    Path('ios-driver-exit.txt').write_text('0')


if __name__ == '__main__':
    main()
