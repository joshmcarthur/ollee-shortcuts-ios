# Free Ollee 2

Native iPhone companion for the [Ollee Watch](https://www.olleewatch.com/). It pairs over Bluetooth, pushes a 6-character name tag, beeps, shows a clock-face counter 0–7, and exposes those actions to Shortcuts (including from Apple Watch). RGB backlight write is not in the public command catalogue yet; see below.

This is original Swift. It is not a port of [Arthur86000/FreeOllee](https://github.com/Arthur86000/FreeOllee) or of Super FreeOllee. Protocol facts (Nordic UART, CRC-16/CCITT-FALSE, name-tag target `0x2F`) come from published notes and Gadgetbridge’s Ollee work (PR 6411 lineage).

## Credits

- [Arthur86000/FreeOllee](https://github.com/Arthur86000/FreeOllee) — first open companion; thank you.
- Ollee Watch by Ollee Technologies Inc.
- Hero art is an original orca/ocean homage. It is not the *Free Willy 2* movie poster and does not embed studio stills.

## Requirements

- iOS 17+, iPhone, Xcode 16
- Close the official Ollee app while using this (same radio).
- Signing is Automatic — pick your personal team on first local run. This repo has no Apple Developer team.

Turn the watch radio on: hold **ALARM** on Clock, or tap until **LAP** blinks.

## What the app ships

- Name tag (max 6 ASCII), beep, clock counter 0–7
- App Intents / App Shortcuts so Shortcuts on iPhone or Apple Watch can drive the phone’s BLE session
- A Shortcuts recipe in [`Examples/`](Examples/) for notification → clamp 0–7 → clock counter. You import it; the app does not silently install automations.

Shortcut builders own increment/reset policy. The app only accepts an integer 0–7.

## Light

RGB/backlight write is **not** published in the command catalogue used here (Gadgetbridge Ollee support and the FreeOllee-Faces protocol notes). The UI and the light intent fail closed until a register is confirmed with a golden vector.

## Build

```bash
swift test                          # OlleeFrames, Linux- or macOS-runnable
open FreeOllee2.xcodeproj           # iOS app; enable your team to run on a phone
```

Zero Swift package dependencies. Dependabot watches GitHub Actions only.

## Protocol (short)

Frames on Nordic UART (`6E400001-B5A3-F393-E0A9-E50E24DCCA9E`):

```
00 LEN AA 55 CRC-HI CRC-LO 02 TARGET PAYLOAD…
```

CRC-16/CCITT-FALSE over `02 TARGET PAYLOAD`. Writes are chunked at 20 bytes. Name tag is `02 2F`. Beep is alarm-record `playNow` on `02 25` so a new alarm is not persisted. Clock counter writes weekday names on `02 34` while keeping the World Time offset header.
