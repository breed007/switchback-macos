# Changelog

All notable changes to Switchback are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [0.5.0] — 2026-10-04

### Added
- **Passwordless switching.** A privileged helper (an `SMAppService` daemon) switches
  locations without a password once you approve it, for standard users too. It can
  only switch to an existing location, accepts requests only from Switchback, and
  logs each switch. Creating, renaming, and deleting still ask for an administrator.
  Set it up from the menu with **Set Up Passwordless Switching…**.
- **IT policy.** A managed `RequireAdminToSwitch` preference requires admin rights to
  switch. A sample MDM profile is in `docs/mdm/`.
- **Manage Locations window.** Rename in place, delete, and drag to reorder; the menu
  follows your order. It replaces the Manage Locations submenu.
- **Name checks as you type**, in the New Location dialog and when renaming.
- **Shortcuts and Focus.** Switch Network Location and Get Current Network Location
  actions, Spotlight and Siri phrases, and a Focus filter. Switches made this way post
  a notification, and a Focus never asks for a password.
- **Menu.** A live line under the current location (connection, address, DNS), the
  location's name next to the icon after a switch, an option to keep it there, and
  ⌘1 to ⌘9.
- **Launch at Login.**

### Changed
- If the helper can't be reached or refuses by policy, a switch falls back to the
  password prompt.
- Service counts skip interfaces macOS hides from its settings, so they match System
  Settings.

### Fixed
- **Emoji and invisible characters in names.** v0.1.1 split emoji built with a
  zero-width joiner ("👨‍👩‍👧" became "👨 👩 👧") and turned zero-width spaces into
  visible ones. Names that only look alike, such as full-width letters or names with
  invisible characters, now count as duplicates.
- Choosing the location you're already on no longer asks for a password.

### Not yet tested
This release shipped with these untested (details in `docs/v0.5-spec.md`):
- A switch between two different locations through the helper. The helper's switch
  was tested by re-applying the current location.
- Standard-user switching and helper approval, and the MDM profile and
  `RequireAdminToSwitch` with a real MDM.
- Shortcuts, Siri, Spotlight, and Focus filters end to end, and the notifications.
- The window and dialogs by eye: layout, drag to reorder, keyboard use, VoiceOver.
- macOS 14, and Intel Macs.

## [0.1.1] — 2026-07-01

### Fixed
- **Cancelling the macOS auth panel is now a silent no-op** instead of popping a
  "couldn't complete that change" error — for switch, create, rename, and delete.
- **The menu reads live system state every time it opens**, so an external
  location switch (System Settings, `scselect`) is always reflected. The previous
  event-only refresh could miss switches between locations with matching IP config,
  because the current-set pointer isn't an `SCDynamicStore` key.
- **Privileged changes run off the main thread**, so the menu bar no longer freezes
  while macOS applies a location switch.

### Changed
- Location names are sanitized: control characters and embedded newlines are
  stripped and length is capped at 128, so a pasted block of text can't become a
  location name.
- Deleting a location is guarded by identity, not just name — the current location
  and the last remaining location can't be deleted, each with a clear message.
- Creating a location that would end up with zero services now fails cleanly
  instead of producing an empty, non-functional location.
- The empty-state menu now offers **New Location…**, and re-entrant privileged
  actions are ignored while one is already in flight.

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
