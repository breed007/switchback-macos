# Privacy — Switchback

Switchback is a local utility. It is built so there is nothing to collect.

## What Switchback does

- Reads your macOS **network locations** and which one is current, using Apple's
  SystemConfiguration framework. This is read-only local system state.
- Switches the active location when you choose one, by committing a change through
  the operating system's own authorization mechanism (the native "is trying to make
  changes" panel).

## What Switchback does **not** do

- **No network connections.** Switchback makes no outbound requests of any kind.
- **No telemetry or analytics.** No usage data, crash pings, or identifiers are
  collected or transmitted.
- **No data storage.** Switchback does not persist your network configuration or any
  personal data off-device. It does not keep logs.
- **No third-party SDKs.**

## Permissions

Switchback requires authorization only at the moment you switch a location, granted
through the standard macOS authorization panel. It installs no background services and
no passwordless `sudo` rules.

## Contact

Questions: open an issue at https://github.com/breed007/switchback-macos/issues
