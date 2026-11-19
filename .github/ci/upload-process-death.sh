#!/bin/sh
# One install only. Recover by attaching to a relaunched same binary, no rebuild.
set -eu
cd app
mkdir -p build/screenshots
marker=$(openssl rand -hex 24)
timeout 600 flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/upload_process_death_test.dart --no-pub --keep-app-running \
  --dart-define=MARKER_ID="$marker" > build/screenshots/process_death_seed.log 2>&1 || {
    tail -100 build/screenshots/process_death_seed.log; exit 1;
  }
tail -6 build/screenshots/process_death_seed.log
adb shell dumpsys package au.fintex.sanjaal | grep 'userId=' > build/screenshots/process_death_uid_before.log
adb shell pm path au.fintex.sanjaal > build/screenshots/process_death_package_before.log
# A native app-private sentinel proves the second phase retains ordinary files too.
adb shell run-as au.fintex.sanjaal touch files/synthetic-marker-recover
adb shell am force-stop au.fintex.sanjaal
if adb shell pidof au.fintex.sanjaal; then
  echo 'App process still present after force-stop'; exit 1;
fi
echo 'FORCE_STOP_CONFIRMED no app PID; one install; no uninstall/clear' | tee build/screenshots/process_death_stop.log
adb logcat -c
adb shell am start -n au.fintex.sanjaal/.MainActivity \
  --ez enable-dart-profiling true --ez enable-checked-mode true \
  --ez verify-entry-points true --ez start-paused true > build/screenshots/process_death_launch.log
# Wait for this new process's VM-service ready signal, not a fixed startup sleep.
uri=''
for i in $(seq 1 60); do
  uri=$(adb logcat -d | sed -n 's/.*Dart VM service is listening on \(http:\/\/127\.0\.0\.1:[0-9]*\/[^ ]*\).*/\1/p' | tail -1)
  [ -n "$uri" ] && break
  sleep 1
done
[ -n "$uri" ] || { adb logcat -d | tail -80; exit 1; }
remote_port=$(printf '%s' "$uri" | sed -n 's|http://127.0.0.1:\([0-9]*\)/.*|\1|p')
[ -n "$remote_port" ]
adb forward tcp:8181 "tcp:$remote_port"
local_uri=$(printf '%s' "$uri" | sed "s/:$remote_port\//:8181\//")
adb shell dumpsys package au.fintex.sanjaal | grep 'userId=' > build/screenshots/process_death_uid_after.log
adb shell pm path au.fintex.sanjaal > build/screenshots/process_death_package_after.log
diff build/screenshots/process_death_uid_before.log build/screenshots/process_death_uid_after.log
diff build/screenshots/process_death_package_before.log build/screenshots/process_death_package_after.log
timeout 180 flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/upload_process_death_test.dart --no-pub \
  --use-existing-app="$local_uri" > build/screenshots/process_death_recover.log 2>&1 || {
    tail -100 build/screenshots/process_death_recover.log; exit 1;
  }
tail -6 build/screenshots/process_death_recover.log
grep -F 'PROCESS_DEATH_SEED native marker read-back verified' build/screenshots/process_death_seed.log
grep -F 'PROCESS_DEATH_RECOVERY exact native marker survived process restart' build/screenshots/process_death_recover.log
