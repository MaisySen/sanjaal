#!/bin/sh
# No API, Auth0 or user account. Only a synthetic native secure-storage marker.
set -eu
cd app
mkdir -p build/screenshots
marker=$(openssl rand -hex 24)
for phase in seed recover; do
  timeout 600 flutter drive --driver=test_driver/integration_test.dart \
    --target=integration_test/upload_process_death_test.dart --no-pub \
    --dart-define=MARKER_PHASE="$phase" --dart-define=MARKER_ID="$marker" \
    > "build/screenshots/process_death_$phase.log" 2>&1 || {
      tail -100 "build/screenshots/process_death_$phase.log"
      exit 1
    }
  tail -6 "build/screenshots/process_death_$phase.log"
  if [ "$phase" = seed ]; then
    adb shell am force-stop au.fintex.sanjaal
    if adb shell pidof au.fintex.sanjaal; then
      echo 'App process still present after force-stop'
      exit 1
    fi
    echo 'FORCE_STOP_CONFIRMED no app PID; package data retained; no uninstall/clear' | tee build/screenshots/process_death_stop.log
  fi
done
grep -F 'PROCESS_DEATH_SEED native marker read-back verified' build/screenshots/process_death_seed.log
grep -F 'PROCESS_DEATH_RECOVERY exact native marker survived process restart' build/screenshots/process_death_recover.log
