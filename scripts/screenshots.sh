#!/usr/bin/env bash
#
# screenshots.sh — regenerate the README screenshots from the real UI, with sample data.
#
# Builds nothing itself: run scripts/dev-build.sh first (it needs the Debug-only
# `--demo` mode). For each piece of UI and each appearance, it launches the Debug app
# in demo mode (sample locations and network details, never this Mac's), finds that
# process's window by PID, captures only that window, and quits the demo. Nothing
# else on screen can end up in an image.
#
# Needs Screen Recording permission for whatever runs it (macOS asks once).
#
#   scripts/screenshots.sh                 # all: menu, manage, dialog
#   scripts/screenshots.sh dialog          # just these
#
set -euo pipefail
cd "$(dirname "$0")/.."

BIN="build/dev/Build/Products/Debug/Switchback.app/Contents/MacOS/Switchback"
OUT="docs/screenshots"
FINDER="build/dev/window-for-pid"
[ -x "$BIN" ] || { echo "run scripts/dev-build.sh first"; exit 1; }
mkdir -p "$OUT"

# Tiny helper: print "x y width height" (points, top-left origin) of the frontmost
# window a PID owns, skipping the capture backdrop, the menu-bar status item (short),
# and invisible windows. The highest layer wins.
if [ ! -x "$FINDER" ] || [ "$0" -nt "$FINDER" ]; then
  cat > build/dev/window-for-pid.swift <<'SWIFT'
import CoreGraphics
import Foundation
let pid = Int32(CommandLine.arguments[1])!
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
let candidates = windows.filter { w in
    guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
          (w[kCGWindowName as String] as? String) != "SwitchbackDemoBackdrop",
          let bounds = w[kCGWindowBounds as String] as? [String: CGFloat],
          (bounds["Height"] ?? 0) > 50, (w[kCGWindowAlpha as String] as? CGFloat ?? 1) > 0 else { return false }
    return true
}
let best = candidates.max { ($0[kCGWindowLayer as String] as? Int ?? 0) < ($1[kCGWindowLayer as String] as? Int ?? 0) }
guard let b = best?[kCGWindowBounds as String] as? [String: CGFloat] else { exit(1) }
print(Int(b["X"]!), Int(b["Y"]!), Int(b["Width"]!), Int(b["Height"]!))
SWIFT
  swiftc -O build/dev/window-for-pid.swift -o "$FINDER"
fi

for what in ${@:-menu manage dialog}; do
  for look in light dark; do
    "$BIN" --demo "$what" "$look" >/dev/null 2>&1 &
    pid=$!
    # Wait until the window's bounds read the same twice in a row (up to ~8 s): a
    # dialog can be on screen mid-layout at a smaller size before it settles.
    bounds=""; prev=""
    for _ in $(seq 1 40); do
      sleep 0.2
      bounds=$("$FINDER" "$pid" 2>/dev/null) || bounds=""
      [ -n "$bounds" ] && [ "$bounds" = "$prev" ] && break
      prev="$bounds"
    done
    sleep 0.6                         # let it finish drawing
    if [ -n "$bounds" ]; then
      # Capture the composited region (so materials blend with the backdrop), with
      # room for the shadow. The backdrop covers the menu bar too, so the margin
      # above a menu is backdrop, not menu bar.
      read -r x y w h <<< "$bounds"
      top=$([ "$what" = menu ] && echo 12 || echo 24)
      x=$(( x - 32 )); y=$(( y - top )); w=$(( w + 64 )); h=$(( h + top + 48 ))
      screencapture -x -R "$x,$y,$w,$h" "$OUT/$what-$look.png"
      echo "captured $OUT/$what-$look.png"
    else
      echo "FAILED: no window for $what ($look)"
    fi
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
done
