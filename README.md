# Minix Insight

Native macOS menu bar app for collecting X.Tips miniX physical key telemetry over QMK Raw HID.

The app records physical matrix events, not system text input. It is intended for ergonomic analysis of a custom QMK keyboard.

## Current MVP

- Menu bar status item
- Raw HID device detection for `5262:4e4b`
- Event logging to local SQLite
- Today summary in the menu
- Pause/resume logging
- Export today's events as CSV

## Build

```bash
swift build
./scripts/package_app.sh
open dist/Minix\ Insight.app
```

The packaged app stores data under:

```text
~/Library/Application Support/Minix Insight/minix-insight.sqlite3
```

Close Vial/WebHID while logging. They use the same Raw HID interface.

## Firmware Protocol

Minix Insight expects the QMK firmware to send 32-byte Raw HID reports:

| Bytes | Field |
| --- | --- |
| 0...1 | ASCII magic `KS` |
| 2 | protocol version, currently `1` |
| 3 | event type, currently `1` for key event |
| 4 | matrix row |
| 5 | matrix column |
| 6 | pressed flag, `1` down and `0` up |
| 7 | active layer |
| 8...11 | QMK `timer_read32()` milliseconds, little-endian |
| 12...13 | QMK keycode, little-endian |
| 14...17 | event sequence, little-endian |

The host computes hold duration by pairing down/up events per physical matrix position.

## Notes

This app does not use macOS Accessibility APIs and does not read system text input. It only reads the keyboard's vendor-defined Raw HID interface.
