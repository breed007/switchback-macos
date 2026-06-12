# SETUP — Switchback

This repo ships **source + an XcodeGen spec** rather than a checked-in `.xcodeproj`,
so the project file is always generated cleanly. Two ways to get an Xcode project:

## Path A — XcodeGen (recommended)

```sh
brew install xcodegen
cd switchback-macos
xcodegen generate
open Switchback.xcodeproj
```

`project.yml` defines the target, bundle ID (`com.breed007.switchback`), deployment
target (macOS 14), and enables Hardened Runtime for notarization. Set your
`DEVELOPMENT_TEAM` (Team ID) in `project.yml` or in Xcode's Signing & Capabilities.

## Path B — Manual Xcode project (no XcodeGen)

1. Xcode → **File ▸ New ▸ Project… ▸ macOS ▸ App**.
2. Product Name **Switchback**, Interface **AppKit** (or "XIB"/none), Language Swift,
   bundle ID `com.breed007.switchback`, deployment target **macOS 14**.
3. Delete the template's `AppDelegate`/`main`/storyboard, then drag the files from the
   `Switchback/` source folder into the target (check "Copy items if needed" off if
   they're already in place).
4. In the target's **Info** tab add **Application is agent (UIElement) = YES**
   (`LSUIElement`), or keep the provided `Info.plist` and point `INFOPLIST_FILE` at it.
5. **Signing & Capabilities:** select your Team, enable **Hardened Runtime**. Do **not**
   add the App Sandbox capability — the privileged location switch can't run sandboxed.

## Notarizing a release

```sh
xcodebuild -project Switchback.xcodeproj -scheme Switchback -configuration Release \
  -derivedDataPath build archive   # or use Xcode ▸ Product ▸ Archive
# then: xcrun notarytool submit ... --wait  and  xcrun stapler staple Switchback.app
```

Because Switchback uses `AuthorizationRef` (not a sudoers rule) and you hold a paid
Developer ID, ship it **notarized** for a quarantine-free install.
