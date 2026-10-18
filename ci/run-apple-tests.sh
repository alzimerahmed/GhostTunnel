#!/bin/bash
cd app-apple && FOR_TESTING=1 swift test
status=$?
if [ $status -ne 0 ]; then
  sleep 2
  latest=$(ls -t ~/Library/Logs/DiagnosticReports/*.ips 2>/dev/null | head -5)
  echo "=== Recent crash reports ==="
  for f in $latest; do
    echo "--- $f ---"
    head -c 20000 "$f"
    echo
  done
fi
exit $status
