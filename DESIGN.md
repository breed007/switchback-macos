# DESIGN.md — Switchback

This document explains *why* Switchback is built the way it is, and the reasoning
behind each thing it deliberately does **not** do. For the build/architecture
reference Claude Code uses, see `CLAUDE.md`.

---

## Philosophy: one job, done well

Switchback sees and switches macOS **network locations** from the menu bar. That is
the entire app. Like its sibling Crossbar, it earns its place by collapsing a real,
recurring annoyance into a single click — not by accumulating features.

The annoyance is concrete. macOS locations (named sets of network settings — service
order, IP config, DNS, proxies) still exist, but Apple buried them. As of macOS
Sequoia/Tahoe the path is **System Settings → Network → "⋯" → Locations → Edit
Locations**, several clicks deep, and the switch only commits when you *quit* System
Settings. There is no longer a Location dropdown at the top of the Network pane like
the old System Preferences had, so most people assume the feature was removed.

It wasn't. Switchback surfaces it: every location, the current one marked, one click
to switch. For consultants and engineers who move between client sites — each needing
a different service order or static-IP profile — that one click replaces a multi-step
detour every single time.

## The core insight: a privilege boundary

Switchback is built around the same fact as Crossbar:

> **Reading location state is unprivileged. Changing it requires root.**

Everything in the design follows from respecting that boundary cleanly. The read side
is rich, live, and free; the write side is small, explicit, and gated. The UI only
ever talks to a protocol seam, so the privileged half can be replaced without
touching anything the user sees.

## Key design decisions

### AuthorizationRef over a sudoers rule

Crossbar's v1 backend shells out to `networksetup` via a passwordless `sudo` rule the
user installs in `/etc/sudoers.d`. It works, but it costs the user a setup step and a
paragraph of explanation, and it can't be notarized cleanly.

Switchback takes the **`AuthorizationRef` + `SCPreferences`** path instead. Opening
preferences with `SCPreferencesCreateWithAuthorization` and committing changes
triggers the **native macOS "is trying to make changes" auth panel** — the same prompt
users already trust from System Settings. The benefits compound:

- **No setup friction.** No sudoers file, no README install ritual. The app just works.
- **Smaller security surface.** No standing passwordless rule sitting on disk; auth is
  per-action and system-mediated.
- **Notarizable.** The developer holds a paid Apple Developer ID, and this model needs
  no sudoers rule, so the build can be Developer ID-signed and notarized — a cleaner
  install than Crossbar could offer.

The `scselect` / `networksetup` shell-out remains documented as a fallback, but only
if the AuthorizationRef path proves impractical, because it would drag the sudoers
requirement back in.

### Event-driven reads, never polling

Like Crossbar, the read layer subscribes to `SCDynamicStore` and refreshes only when
network state actually changes. Polling would burn cycles to mostly observe nothing;
an event-driven monitor is both lighter and more correct (the menu is right the instant
something changes, including changes Switchback didn't initiate).

### AppKit, no dependencies

Switchback mirrors Crossbar: native Swift + AppKit, a menu-bar **agent** (no Dock
icon, no app-switcher entry), zero third-party code. Consistency with Crossbar keeps
both repos legible to the same contributors, and AppKit's status-item maturity fits a
resting-in-the-menu-bar tool. The whole point is a small, auditable binary.

### Minimal management, not a settings editor

Switchback will switch locations and minimally manage them (create / rename / delete).
It stops there. Editing the *contents* of a location — per-service IP, DNS, proxy, VPN
config — is explicitly out (see non-goals). The app is a fast switcher, not a
replacement for Apple's network configuration surface.

## Non-goals, and the reasoning behind each

Switchback's restraint is a feature. Each exclusion below is deliberate.

### It does not toggle network services (Wi-Fi / Ethernet / VPN on/off)

That is **Crossbar's** job. This boundary is the entire reason both apps exist as
separate tools. Folding service toggling into Switchback (or locations into Crossbar)
would bloat both and blur two genuinely different mental models: *"which setup am I
using"* (locations) versus *"is this connection on"* (services). Two focused tools beat
one cluttered one — and for a reputation-building open-source line, focus is the brand.

### It does not edit per-service settings within a location

Defer to Apple's Network pane via a "Network Settings…" link. Replicating the IP / DNS
/ proxy / VPN configuration UI would be a deep, perpetually-maintained surface that
Apple already does well, and every field that accepts input is a new validation and
security concern. Switchback's value is *switching between* configured locations, not
authoring their internals.

### It does not auto-switch by rules (SSID, geofence, time)

That is ControlPlane territory, and it is out of scope on purpose. Rule-based
auto-switching turns a predictable, user-initiated tool into a background engine that
changes your network out from under you — exactly the kind of "why did my connection
just change?" surprise the app is meant to eliminate. Switchback stays manual and
predictable. If automation is wanted, that's a different product with a different risk
profile.

### It is not bundled with Crossbar into one "network menu" app

Tempting, rejected. A combined app would carry two privilege models, two feature sets,
and a muddier value proposition. Shipping them separately lets each stay
single-purpose, lets users install only what they need, and lets each succeed or fail
on its own merits.

## Future considerations

- **XPC / `SMAppService` backend.** If `AuthorizationRef` proves limiting, a privileged
  helper over XPC is the natural next step — and the `LocationSwitcher` protocol seam
  exists precisely so that swap costs nothing in the UI.
- **Cross-platform brand.** The `switchback-macos` repo name reserves room for future
  siblings, but the design does not pretend the SystemConfiguration layer ports. The
  *concept* ("switch between named network setups") travels; a Linux build would target
  NetworkManager profiles, Windows its own network profiles. Each is its own
  implementation under a shared name — not a port of this code.
