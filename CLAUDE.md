# CLAUDE.md — Switchback

> Menu-bar agent to view and switch macOS **network locations** with one click —
> without digging through System Settings.

This file orients Claude Code on Switchback. Read it before making changes. Keep
edits focused on the app's one job; see **Scope & non-goals** before adding anything.

---

## What Switchback is

macOS network **locations** (sets of network settings — service order, IP config,
DNS, etc.) still exist, but Apple buried them. As of macOS Sequoia/Tahoe the only
path is **System Settings → Network → "⋯" More menu → Locations → Edit Locations**,
several clicks deep, and you must quit System Settings to commit the switch. Most
people think the feature was removed.

Switchback collapses that into a menu-bar dropdown: every location, the current one
marked, one click to switch. Optionally create/rename/delete locations. That's the
whole app.

It is the open-source sibling to **Crossbar** (`crossbar-macos`), which toggles
network *services*. Switchback switches *locations*. The two deliberately do not
overlap — see non-goals.

## Status

Pre-1.0. Greenfield. Mirror Crossbar's structure and conventions where possible.

## Tech stack

- **Swift + AppKit**, native menu-bar agent (`LSUIElement` / agent app, no Dock icon).
- **SystemConfiguration** framework (`SCNetworkSet`, `SCPreferences`, `SCDynamicStore`).
- **No third-party dependencies.** Keep it that way.
- Minimum target: **macOS 14 (Sonoma)**. Build with current Xcode.
- Universal binary (Apple Silicon + Intel).

## Build & run

```sh
open Switchback.xcodeproj            # press ▶ Run, or:
xcodebuild -project Switchback.xcodeproj -scheme Switchback -configuration Release build
```

Then copy the built `Switchback.app` to `/Applications`.

## Architecture

Switchback is built around one fact, exactly like Crossbar:
**reading location state is unprivileged; changing it requires root.**
Those two halves are separated by a clean privilege boundary.

### Read layer (unprivileged)

- Open a read-only `SCPreferences` (`SCPreferencesCreate`).
- Enumerate locations with `SCNetworkSetCopyAll`; name each via `SCNetworkSetGetName`.
- Identify the active location with `SCNetworkSetCopyCurrent` →
  `SCNetworkSetGetSetID` / name, to render the checkmark.
- Stay **event-driven** (no polling): subscribe via `SCDynamicStore` to changes in
  `Setup:/` (the current set changes there) and refresh the model when state actually
  changes. Follow Crossbar's `StatusMonitor` pattern.

### Write layer (privileged) — the seam

Define a `LocationSwitcher` protocol (the seam), mirroring Crossbar's
`PrivilegedToggle`. The UI knows only the protocol, so the backend can be swapped
without touching the interface.

**Primary backend — `AuthorizationRef` + SCPreferences (preferred):**

- Acquire an `AuthorizationRef`, open prefs with
  `SCPreferencesCreateWithAuthorization`.
- Set the current set with `SCNetworkSetSetCurrent`, then
  `SCPreferencesCommitChanges` + `SCPreferencesApplyChanges`.
- The commit triggers the **native macOS "is trying to make changes" auth panel** —
  no sudoers rule, no `/etc/sudoers.d` setup step. This is the documented Apple path
  and is a genuine upgrade over Crossbar's v1 sudoers backend.
- Create/rename/delete locations (`SCNetworkSetCreate`, `SCNetworkSetSetName`,
  `SCNetworkSetRemove`) are also privileged commits through this same backend.

**Fallback backend — shell-out (only if AuthorizationRef proves painful):**

- `scselect <location>` to switch; `networksetup -switchtolocation`,
  `-createlocation`, `-deletelocation` to manage. All require root.
- If used, mirror Crossbar exactly: pass args as an **array, never a shell string**;
  validate location names against the live set; serialize operations. This path
  would reintroduce the sudoers requirement, so prefer the AuthorizationRef backend.

## Proposed file layout (mirror Crossbar)

```
Switchback/
  AppDelegate.swift          # agent lifecycle, status item
  StatusItemController.swift # menu-bar icon + popover
  LocationModel.swift        # value types for a location + current marker
  StatusMonitor.swift        # SCDynamicStore event-driven reads
  LocationSwitcher.swift     # protocol (the seam)
  AuthorizedSwitcher.swift   # AuthorizationRef + SCPreferences backend
  Views/                     # AppKit popover UI
Switchback.xcodeproj
docs/                        # popover.png, details.png, screenshots
DESIGN.md  README.md  CHANGELOG.md  LICENSE
```

## Edge cases Claude Code must handle

- **Single-location users.** A Mac with only the default "Automatic" location gets a
  useless list. Detect this; either guide the user to create locations or surface the
  create flow prominently. Don't ship a one-item menu with no affordance.
- **"Automatic" is special** — it includes all detected services and is the default;
  don't let it be deleted or renamed in a way that breaks the system.
- **Commit semantics** — a switch only fully takes effect after
  `SCPreferencesApplyChanges`; surface success/failure clearly.
- **Auth cancellation** — user can cancel the auth panel; treat as a no-op, not an error.

## Scope & non-goals

Switchback does **one thing well**: see and switch (and minimally manage) network
locations from the menu bar. It intentionally does **NOT** do:

- **Network service toggling** (Wi-Fi/Ethernet/VPN on/off) — that is **Crossbar's**
  job. This boundary is the whole reason both apps exist; do not blur it.
- **Per-service settings editing** (IP/DNS/proxy/VPN config *within* a location) —
  defer to Apple's Network pane via a "Network Settings…" link.
- Location auto-switching by rules/SSID/geofence (that's ControlPlane territory; out
  of scope — keep it manual and predictable).

When users need the excluded features, open Apple's native Network pane.

## Distribution

- **GitHub open source** at `breed007/switchback-macos`, **MIT**, sibling to Crossbar.
- Distribute via **GitHub Releases** + ideally a **Homebrew cask** (`brew install --cask switchback`) — this is how the target audience (IT/network folks) wants to install.
- **Notarization:** unlike Crossbar, the developer holds a paid Apple Developer ID, and
  Switchback's AuthorizationRef model needs no sudoers rule — so **notarize the build**
  (Developer ID + `xcrun notarytool`) for a clean, quarantine-free install. Keep a
  documented un-notarized "Open Anyway" path in the README as a fallback.

## Branding & conventions

- Personal open-source project under `breed007` (not the 404 Tools commercial brand).
  Match Crossbar's identity, license header style, and README tone.
- Bundle ID: follow Crossbar's scheme (personal reverse-DNS, e.g.
  `com.breed007.switchback` — confirm against Crossbar's actual ID).
- Code style: native Swift + AppKit, no dependencies, small and legible. Match Crossbar.

## Cross-platform note (future)

The `switchback-macos` repo name reserves the suffix for later `-windows` / `-linux`
/ `-ios` siblings. **Be honest in design: macOS network "locations" are an
`SCNetworkSet` construct with no 1:1 port.** A Linux build would target NetworkManager
connection profiles; Windows would target network profiles. The *brand* and *concept*
("switch between named network setups") carry across; the *implementation* does not.
Don't design the macOS code assuming portability of the SystemConfiguration layer.
