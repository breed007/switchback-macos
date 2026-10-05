# Switchback

**See and switch macOS network *locations* from the menu bar, without digging through
System Settings.**

![Platform](https://img.shields.io/badge/macOS-14%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Language](https://img.shields.io/badge/Swift-AppKit-orange)

Switchback is the open-source sibling to [Crossbar](https://github.com/breed007/crossbar-macos).
Crossbar toggles network *services* (Wi-Fi, Ethernet, VPN). Switchback switches network
*locations*: the named sets of network settings Apple buried so deep that most people
think the feature was removed.

## Why Switchback?

macOS **locations** still exist, but as of Sonoma, Sequoia, and Tahoe the only way to
reach them is **System Settings → Network → "⋯" (More) → Locations → Edit Locations**,
several clicks deep, and a switch only commits when you *quit* System Settings. The
Location menu the old System Preferences had is gone, so the feature feels gone too.

Switchback puts every location one click away in the menu bar, with the current one
marked. If you move between client sites that each need a different service order or
static-IP setup, that's a multi-step detour replaced by a single click.

## What it does

- **Lists your locations** with the current one checked, and a live line under it
  showing the connection, address, and DNS servers.
- **Switches in one click**, with no password once passwordless switching is set up
  (see below). ⌘1 to ⌘9 switch to the first nine while the menu is open.
- **Manages locations** in a Manage Locations window: create, rename in place,
  delete, and drag to set the order the menu uses. Names are checked as you type,
  so lookalike or duplicate names can't slip in.
- **Works with Shortcuts and Focus**: a Switch Network Location action, a Get Current
  Network Location action, Spotlight and Siri phrases, and a Focus filter that
  switches when a Focus turns on.
- **Shows what changed**: the new location's name appears next to the icon after a
  switch, and switches made by Shortcuts or a Focus post a notification. You can also
  keep the name in the menu bar.
- **Launches at login**, if you want it to.

## Requirements

- **macOS 14 (Sonoma) or later** to run.
- **Xcode 16+** and **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** only if you
  build from source (see below).

## Install

### Option 1: Homebrew (recommended)

```sh
brew tap breed007/tap
brew trust breed007/tap          # one-time; Homebrew requires trusting third-party taps
brew install --cask switchback
```

### Option 2: Download the prebuilt app

Grab the latest `Switchback-vX.Y.Z-universal.zip` (or the `.dmg`) from
[Releases](https://github.com/breed007/switchback-macos/releases/latest), unzip it, and
move **Switchback.app** to `/Applications`. The app is universal (Apple silicon and
Intel) and notarized, so it opens with no Gatekeeper workaround.

### Option 3: Build from source

```sh
git clone https://github.com/breed007/switchback-macos.git
cd switchback-macos
brew install xcodegen        # one-time
xcodegen generate            # produces Switchback.xcodeproj from project.yml
open Switchback.xcodeproj    # press ▶ Run
```

See [SETUP.md](SETUP.md) for the manual (no XcodeGen) path. A build you make yourself
isn't notarized: the first time you open it, choose **Open Anyway** in **System
Settings → Privacy & Security**.

## Passwordless switching

Out of the box, every switch asks for an administrator's password, because changing
the network configuration needs root. To switch with one click instead, choose
**Set Up Passwordless Switching…** in Switchback's menu, then turn on Switchback in
**System Settings → General → Login Items & Extensions**. Approving it takes an
administrator's password, once.

This installs a small helper that can do exactly one thing: make an existing location
current. It accepts requests only from Switchback, and it logs each switch to the Mac's
unified log. Creating, renaming, and deleting locations still ask for an administrator,
because they change configuration.

**Standard (non-admin) users** can switch once the helper is approved, because they can
only move between locations an administrator already set up. Locations apply to the
whole Mac, so a switch affects every account on it.

### For IT: deploying with MDM

[`docs/mdm/switchback-sample.mobileconfig`](docs/mdm/switchback-sample.mobileconfig) is
a sample device profile that:

- pre-approves the helper (a Managed Login Items rule for its launchd label,
  `com.breed007.switchback.helper`), so users never see the approval step, and
- sets **`RequireAdminToSwitch`** in the `com.breed007.switchback` domain. `false`, the
  default, lets any local user switch; `true` requires an administrator, and other
  users get the password prompt instead.

The helper reads the policy only from the computer-level managed preferences
(`/Library/Managed Preferences/com.breed007.switchback.plist`), never from settings a
user can write. To audit switches:

```sh
/usr/bin/log show --predicate 'subsystem == "com.breed007.switchback.helper"' --last 1d
```

The sample profile hasn't been tested against a real MDM enrollment yet. Try it on a
test machine first, and please open an issue with what you find.

## Shortcuts and Focus

- In **Shortcuts**, search for "Switchback" to find **Switch Network Location** and
  **Get Current Network Location**. To switch with a keyboard shortcut from anywhere,
  give a Switch Network Location shortcut a key combination in Shortcuts.
- In **Spotlight** or with **Siri**, say or type "Switch Switchback location to Office".
- In **System Settings → Focus**, choose a Focus, then **Add Filter → Switchback** and
  pick a location. Switchback switches to it when that Focus turns on. Turning the
  Focus off doesn't switch back.

A Focus never asks for a password. If passwordless switching isn't set up, it skips the
switch and posts a notification saying how to set it up.

## How it works

Switchback is built around one fact: **reading location state is unprivileged;
changing it requires root.**

- **Read layer.** `StatusMonitor` lists locations (`SCNetworkSetCopyAll`) and marks the
  current one (`SCNetworkSetCopyCurrent`). The menu re-reads every time it opens, and
  an `SCDynamicStore` subscription keeps it current while it's open. Nothing polls.
- **Write layer.** A `LocationSwitcher` protocol, with a router behind it. Switches go
  to the privileged helper (an `SMAppService` daemon over XPC) when it's set up, and
  otherwise to an `AuthorizationRef` + `SCPreferences` commit, which shows the macOS
  authorization panel. Create, rename, and delete always use the authorization panel.

Built natively in Swift and AppKit. No third-party dependencies. See
[DESIGN.md](DESIGN.md) for why it's built this way.

## Privacy

- **No network calls, no telemetry, no analytics.** Switchback reads local system
  configuration and changes local locations.
- The helper and the app write to the Mac's unified log (user and location IDs, never
  location names), and nothing leaves your Mac. See [PRIVACY.md](PRIVACY.md).

## Scope (and non-goals)

Switchback does one thing. It does **not** toggle network services (that's Crossbar),
edit settings inside a location (use Apple's Network settings), or switch on its own by
rules, SSID, or geofence. Shortcuts and Focus can trigger a switch, but you write the
rule in Apple's tools. See [DESIGN.md](DESIGN.md) for the reasoning behind each
non-goal.

## Contributing

Issues and PRs welcome. Switchback is intentionally small, so please keep changes
focused on its one job: seeing and switching network locations from the menu bar.

## License

[MIT](LICENSE) © 2026 breed007
