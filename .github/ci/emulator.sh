#!/bin/sh
# Runs both emulator tests, keeps the real exit code, and turns failure lines into annotations.
cd app
rc=0
for t in smoke signed_in; do
  extra=""
  if [ "$t" = signed_in ]; then
    extra="--dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1 --dart-define=E2E_TOKEN=$(cat /tmp/e2e/token.txt)"
  fi
  flutter drive --driver=test_driver/integration_test.dart --target=integration_test/${t}_test.dart --no-pub $extra > /tmp/drive_$t.log 2>&1
  code=$?
  tail -4 /tmp/drive_$t.log | cut -c1-200
  if [ $code -ne 0 ]; then
    rc=$code
    grep -n -E "EXCEPTION|Exception|Expected|Actual|Error|error:|FAILURE|\[E\]|Could not|failed" /tmp/drive_$t.log | head -25 | cut -c1-280 | sed 's/%/%25/g' | while read -r l; do echo "::error title=emulator $t::$l"; done
  fi
done
if [ $rc -ne 0 ]; then tail -8 /tmp/e2e/server.log | cut -c1-240 | sed 's/%/%25/g' | while read -r l; do echo "::error title=local api log::$l"; done; fi
exit $rc
