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

Pre-1.0. v0.5.0 shipped 2026-10-04. Its spec, milestone results, and the list of
what's still untested are in [docs/v0.5-spec.md](docs/v0.5-spec.md). Mirror Crossbar's
structure and conventions where possible.

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

**Shortcuts and Focus (v0.5).** The App Intents live in the app target
(`Intents.swift`), not an extension, so the helper's single-identifier caller check
covers them. The rules (a Focus never prompts; every automated switch is announced)
are in `AutomationSwitch`, which is unit-tested without App Intents. Automation
runs are logged: `/usr/bin/log show --predicate 'subsystem == "com.breed007.switchback" AND category == "automation"'`.

**Hidden interfaces.** macOS hides services on interfaces whose driver has
`HiddenConfiguration = Yes` in the I/O Registry (on Apple silicon, the internal
USB-C networking interfaces, often en4–en6). `SCNetworkInterfaceCopyAll` still
returns them, so `HiddenInterfaces` reads the flag through IOKit; without it the
service counts disagree with System Settings and `networksetup`.

**Testing the privileged helper (v0.5).** The helper only accepts calls from a
Switchback signed by team `YA83Q8FTH3`, so unsigned builds can't reach it. Use
`scripts/dev-build.sh` (Debug, Developer ID signed, installs to `/Applications`),
then drive it from Terminal with the Debug-only flags:
`/Applications/Switchback.app/Contents/MacOS/Switchback --helper-status`
(also `--helper-register`, `--helper-unregister`, `--helper-switch <setID>`,
`--helper-selftest`, `--switch <setID>` through the router, `--policy`,
`--login-item [on|off]`, `--details`, `--locations`, and `--menu` / `--manage` /
`--manage-sample`, which print the real menu and Manage window since computer-use
can't see this agent's UI). After rebuilding, the old helper keeps serving until it
has been idle for 60 seconds; wait it out before testing helper changes. Read its audit log with
`/usr/bin/log show --predicate 'subsystem == "com.breed007.switchback.helper"'`.
In zsh, a bare `log` is a shell builtin and silently does nothing useful.
Unit tests: `scripts/test.sh` (regenerates the project first; the tests need no
privileges).

## Architecture

Switchback is built around one fact, exactly like Crossbar:
**reading location state is unprivileged; changing it requires root.**
Those two halves are separated by a clean privilege boundary.

### Read layer (unprivileged)

- Open a read-only `SCPreferences` (`SCPreferencesCreate`).
- Enumerate locations with `SCNetworkSetCopyAll`; name each via `SCNetworkSetGetName`.
- Identify the active location with `SCNetworkSetCopyCurrent` →
  `SCNetworkSetGetSetID` / name, to render the checkmark.
- Re-read on `menuWillOpen`. That read is the source of truth, because the
  current-set pointer lives in the preferences plist (`CurrentSet`) and is **not** an
  `SCDynamicStore` key; `Setup:/` matches nothing, so a dynamic-store subscription
  alone misses external switches between locations with the same IP setup. Keep the
  `SCDynamicStore` subscription (no polling) only for live updates while the menu is
  open. Follow Crossbar's `StatusMonitor` pattern.

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
- Gotcha: **this prompts for an admin password on every commit.** The right
  (`system.services.systemconfiguration.network`) resolves to
  `authenticate-admin-nonshared` (not shared, 30 s timeout) and each operation frees
  its authorization. Standard users can't switch on this path without an admin's
  credentials. v0.5 adds a root helper for switching; see the spec.
- Create/rename/delete locations (`SCNetworkSetCreate`, `SCNetworkSetSetName`,
  `SCNetworkSetRemove`) are also privileged commits through this same backend.

**v0.5: the privileged helper, and the router.** `SwitchRouter` sends switches to
`SwitchbackHelper`, a root `SMAppService` daemon reached over XPC, when it's enabled,
and otherwise to the `AuthorizationRef` backend. Create, rename, and delete always use
the `AuthorizationRef` backend. The helper has one operation (switch to an existing
set by ID), pins its caller to Switchback's signature, validates the ID, enforces the
managed `RequireAdminToSwitch` policy, and logs each switch. See DESIGN.md and
docs/v0.5-spec.md.

**Fallback backend — shell-out (only if AuthorizationRef proves painful):**

- `scselect <location>` to switch; `networksetup -switchtolocation`,
  `-createlocation`, `-deletelocation` to manage. All require root.
- If used, mirror Crossbar exactly: pass args as an **array, never a shell string**;
  validate location names against the live set; serialize operations. This path
  would reintroduce the sudoers requirement, so prefer the AuthorizationRef backend.

## File layout

```
Switchback/
  main.swift, AppDelegate.swift   # agent lifecycle; notification banners
  StatusItemController.swift      # menu, name flash, Manage window, every action
  ManageLocationsWindowController.swift, NameDialog.swift   # F5 window, F4 dialog
  StatusMonitor.swift             # reads locations (+ live-update subscription)
  LocationModel.swift, LocationOrder.swift, LocationRules.swift,
  LocationNameValidator.swift, NetworkDetails.swift, HiddenInterfaces.swift
  LocationSwitcher.swift          # the protocol (the seam) and its errors
  SwitchRouter.swift              # helper when enabled, else the admin prompt
  AuthorizedSwitcher.swift        # AuthorizationRef + SCPreferences backend
  HelperClient.swift              # SMAppService registration + the XPC call
  Automation.swift, Intents.swift, SwitchNotifier.swift   # Shortcuts/Focus (F7)
  LoginItem.swift, DebugCommands.swift (Debug only)
Helper/      # SwitchbackHelper: the root daemon (one op: switch by set ID)
Shared/      # HelperConstants, HelperPolicy: compiled into app, helper, and tests
Tests/       # unit tests (scripts/test.sh)
scripts/     # dev-build.sh, test.sh, release.sh, generate_icon.swift
docs/        # v0.5-spec.md, mdm/switchback-sample.mobileconfig
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
