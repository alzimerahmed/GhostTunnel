#!/bin/bash
cd app-apple && FOR_TESTING=1 swift test --no-parallel 2>&1 | tail -40
status=${PIPESTATUS[0]}
if [ $status -ne 0 ]; then
  sleep 2
  latest=$(ls -t ~/Library/Logs/DiagnosticReports/*.ips 2>/dev/null | head -3)
  echo "=== Recent crash reports ==="
  for f in $latest; do
    echo "--- $f ---"
    head -c 20000 "$f"
    echo
  done
fi
exit $status
