#!/usr/bin/env bash
#
# dev-build.sh — Debug build signed with the Developer ID, installed to /Applications.
#
# The privileged helper only accepts calls from a Switchback signed by our team, so
# unsigned (CODE_SIGNING_ALLOWED=NO) builds can't exercise it. This build is not
# notarized; it's for local testing only. Use scripts/release.sh for releases.
#
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/dev
LOG="$OUT/build.log"
APP="$OUT/Build/Products/Debug/Switchback.app"
mkdir -p "$OUT"

xcodegen generate >/dev/null

# ENABLE_DEBUG_DYLIB=NO keeps a normal main executable, so its signature and the
# helper's caller check behave exactly as they will in a release build.
if ! xcodebuild -project Switchback.xcodeproj -scheme Switchback -configuration Debug \
    -derivedDataPath "$OUT" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM=YA83Q8FTH3 ENABLE_DEBUG_DYLIB=NO \
    build >"$LOG" 2>&1; then
  grep -E "error:" "$LOG" || tail -20 "$LOG"
  echo "BUILD FAILED (full log: $LOG)"
  exit 1
fi
grep -E "warning:" "$LOG" | grep -v AppIntents || true

codesign --verify --deep --strict "$APP"

pkill -x Switchback 2>/dev/null || true
rm -rf /Applications/Switchback.app
cp -R "$APP" /Applications/
echo "Installed /Applications/Switchback.app (Debug, Developer ID signed, not notarized)"
