#!/usr/bin/env bash
#
# test.sh — regenerate the project and run the unit tests (ad-hoc signed; the tests
# need no privileges and no team signature).
#
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/test

xcodegen generate >/dev/null
if xcodebuild test -project Switchback.xcodeproj -scheme Switchback -destination 'platform=macOS' \
    -derivedDataPath build/test CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    >build/test/test.log 2>&1; then
  grep -E "Executed .* tests" build/test/test.log | tail -1
  echo "TESTS PASSED"
else
  grep -E "error:|failed" build/test/test.log | sort -u | head -30
  echo "TESTS FAILED (full log: build/test/test.log)"
  exit 1
fi
