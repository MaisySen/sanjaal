#!/bin/sh
# Runs both emulator tests, keeps the real exit code, and turns failure lines into annotations.
cd app
rc=0
for t in smoke signed_in flows; do
  extra=""
  if [ "$t" = signed_in ] || [ "$t" = flows ]; then
    extra="--dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1 --dart-define=E2E_TOKEN_BASE=http://10.0.2.2:8000 --dart-define=E2E_TOKEN=$(cat /tmp/e2e/token.txt)"
  fi
  mkdir -p build/screenshots
  adb shell "screenrecord --bit-rate 1500000 --time-limit 170 /sdcard/rec_$t.mp4" > /dev/null 2>&1 &
  sleep 2
  flutter drive --driver=test_driver/integration_test.dart --target=integration_test/${t}_test.dart --no-pub $extra > /tmp/drive_$t.log 2>&1
  code=$?
  adb shell pkill -2 screenrecord > /dev/null 2>&1; sleep 3
  adb pull /sdcard/rec_$t.mp4 build/screenshots/rec_$t.mp4 > /dev/null 2>&1
  tail -4 /tmp/drive_$t.log | cut -c1-200
  if [ $code -ne 0 ]; then
    rc=$code
    grep -n -E "EXCEPTION|Exception|Expected|Actual|Error|error:|FAILURE|\[E\]|Could not|failed" /tmp/drive_$t.log | head -25 | cut -c1-280 | sed 's/%/%25/g' | while read -r l; do echo "::error title=emulator $t::$l"; done
  fi
done
if [ $rc -ne 0 ]; then tail -8 /tmp/e2e/server.log | cut -c1-240 | sed 's/%/%25/g' | while read -r l; do echo "::error title=local api log::$l"; done; fi
exit $rc
