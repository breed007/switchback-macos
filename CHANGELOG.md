# Changelog

All notable changes to Switchback are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [0.1.0] — 2026-06-12

First public release.

### Added
- Menu-bar agent (`LSUIElement`, no Dock icon) with event-driven location reading
  via `SCDynamicStore`, and a `LocationSwitcher` seam backed by an
  `AuthorizationRef` + `SCPreferences` commit (native auth panel, no sudoers rule).
- Location switching: click any location in the menu to make it current. The menu
  reflects changes made anywhere, including in System Settings.
- Location management through the same authorized backend:
  - **New Location…** — creates a location and populates it with one
    default-configured service per attached interface (so it works immediately),
    mirroring `networksetup -createlocation … populate`.
  - **Rename** / **Delete** via a *Manage Locations* submenu. The default
    "Automatic" location is protected from both; the current location can't be
    deleted (switch away first). Delete asks for confirmation.
- Name validation: empty names and case-insensitive duplicates are rejected.
- Single-location Macs get a *New Location…* affordance instead of a dead-end
  one-item menu.
- App icon and menu-bar glyph: a forking "Y" track (arrowheads at the two upper
  tips, a node on the stem) in brushed silver on Crossbar's blue gradient
  squircle — a deliberate sibling to the Crossbar mark. The menu-bar version is a
  monochrome template that adapts to light/dark bars; the New Location dialog
  shows the app icon. Generated from `scripts/generate_icon.swift`.
- Developer ID signing + notarization release pipeline (`scripts/release.sh`,
  `scripts/ExportOptions.plist`): archive → Developer ID export → notarize →
  staple → package as a universal `.zip` and a `.dmg`.
