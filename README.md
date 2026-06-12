# Switchback

**See and switch macOS network *locations* from the menu bar — without digging
through System Settings.**

![Platform](https://img.shields.io/badge/macOS-14%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Language](https://img.shields.io/badge/Swift-AppKit-orange)

Switchback is the open-source sibling to [Crossbar](https://github.com/breed007/crossbar-macos).
Crossbar toggles network *services* (Wi-Fi, Ethernet, VPN…). Switchback switches
network *locations* — the named sets of network settings Apple buried so deep that
most people think the feature was removed.

## Why Switchback?

macOS **locations** still exist, but as of Sonoma/Sequoia/Tahoe the only way to reach
them is **System Settings → Network → "⋯" (More) → Locations → Edit Locations** —
several clicks deep — and a switch only commits when you *quit* System Settings.
There's no longer a Location dropdown at the top of the Network pane like the old
System Preferences had, so the feature feels gone.

Switchback puts every location one click away in the menu bar, with the current one
marked. For anyone who moves between client sites — each needing a different service
order or static-IP profile — that's a multi-step detour replaced by a single click.

## What it does

- **Lists your network locations**, with the active one checked.
- **One-click switch** straight from the menu bar.
- **Reflects changes made anywhere** — if you switch locations in System Settings,
  the menu updates (it's event-driven, not polled).
- **Guides you** when you only have the default "Automatic" location and need to
  create more.

## Requirements

- **macOS 14 (Sonoma) or later** to run.
- **Xcode 16+** and **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** only if you
  build from source (see below).

## Install

### Option 1 — Homebrew (recommended)

```sh
brew tap breed007/tap
brew trust breed007/tap          # one-time — Homebrew requires trusting third-party taps
brew install --cask switchback
```

### Option 2 — Download the prebuilt app

Grab the latest `Switchback-vX.Y.Z-universal.zip` (or the `.dmg`) from
[Releases](https://github.com/breed007/switchback-macos/releases/latest), unzip, and
move **Switchback.app** to `/Applications`. The binary is universal (Apple Silicon +
Intel) and notarized, so it opens with no Gatekeeper workaround.

### Option 3 — Build from source

```sh
git clone https://github.com/breed007/switchback-macos.git
cd switchback-macos
brew install xcodegen        # one-time
xcodegen generate            # produces Switchback.xcodeproj from project.yml
open Switchback.xcodeproj     # press ▶ Run
```

See [SETUP.md](SETUP.md) for the manual (no-XcodeGen) path.

## How it works

Switchback is built around one fact: **reading location state is unprivileged;
changing it requires root.** Those halves are cleanly separated.

- **Read layer** — a `StatusMonitor` backed by `SCDynamicStore`. Fully event-driven:
  it subscribes to network-configuration changes and refreshes only when state
  actually changes. It enumerates locations (`SCNetworkSetCopyAll`) and marks the
  current one (`SCNetworkSetCopyCurrent`).
- **Write layer** — a `LocationSwitcher` protocol (the seam). The default backend
  opens preferences with `SCPreferencesCreateWithAuthorization` and commits via
  `SCNetworkSetSetCurrent` + `SCPreferencesApplyChanges`. The commit triggers the
  **native macOS auth panel** — no sudoers rule, no setup step. Because the UI only
  knows the protocol, a future XPC/`SMAppService` backend could drop in unchanged.

Built natively in Swift + AppKit. No third-party dependencies.

## Privacy

- **No network calls, no telemetry, no analytics.** Switchback only reads local
  system configuration and switches local locations.
- Privileged changes go through the system's own authorization panel; nothing is
  stored or transmitted. See [PRIVACY.md](PRIVACY.md).

## Scope (and non-goals)

Switchback deliberately does one thing well. It intentionally does **not** toggle
network services (that's Crossbar), edit per-service settings inside a location
(defer to Apple's Network pane), or auto-switch by rules/SSID/geofence. See
[DESIGN.md](DESIGN.md) for the reasoning behind each non-goal.

## Contributing

Issues and PRs welcome. Switchback is intentionally small — please keep changes
focused on its one job: seeing and switching network locations from the menu bar.

## License

[MIT](LICENSE) © 2026 breed007
