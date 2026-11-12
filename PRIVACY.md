# Privacy: Switchback

Switchback is a local utility. It is built so there is nothing to collect.

## What Switchback does

- Reads your macOS **network locations**, which one is current, and the current
  connection's address and DNS servers, using Apple's SystemConfiguration framework.
  This is local system state, read without privileges.
- Switches, creates, renames, and deletes locations when you ask. Switching goes
  through Switchback's helper (below) if you've set it up. Everything else goes
  through the macOS authorization panel.
- Keeps a few preferences on your Mac: your location order, whether to show the
  location name in the menu bar, and the update check's setting and last result.

## Update check

Switchback's only network request is its update check, and it's off until you turn
it on:

- With **Check for Updates Automatically** on, Switchback asks GitHub's API
  (`api.github.com/repos/breed007/switchback-macos/releases/latest`) for the latest
  release, at most once a day. **Check for Updates…** asks once, right away.
- The request carries no cookies and nothing about your Mac, your locations, or your
  networks. GitHub sees your IP address, as it does for any web request.
- Switchback keeps the newest version it found, and when it last checked, in its own
  preferences on your Mac. It never downloads or installs anything: a newer version
  opens its release page, or shows the Homebrew command.
- An administrator can turn the check off with the managed `DisableUpdateCheck`
  preference.

## The helper

If you choose **Set Up Passwordless Switching…**, Switchback registers a small
background helper with macOS, which you approve in **System Settings → General →
Login Items & Extensions**. launchd starts it when Switchback asks for a switch, and
it quits after a minute without requests. It can make an existing location current
and nothing else, and it accepts requests only from Switchback signed by its
developer. To remove it, turn it off in Login Items & Extensions.

## Logs

Switchback writes to the Mac's own unified log, which stays on your Mac:

- The helper logs each switch: the local user ID that asked, the location IDs it
  switched from and to, and the result.
- The app logs each request from Shortcuts or a Focus (location IDs only), and each
  time a switch falls back to the password prompt.

Location names are never logged. macOS keeps and rotates these logs, and Switchback
doesn't send them anywhere.

## Notifications

When Shortcuts or a Focus switches your location, Switchback posts a notification.
macOS asks for permission the first time.

## What Switchback does **not** do

- **No network connections.** Switchback makes no outbound requests of any kind.
- **No telemetry or analytics.** No usage data, crash reports, or identifiers are
  collected or transmitted.
- **Nothing leaves your Mac.**
- **No third-party SDKs.**
- **No passwordless `sudo` rules.**

## Contact

Questions: open an issue at https://github.com/breed007/switchback-macos/issues
