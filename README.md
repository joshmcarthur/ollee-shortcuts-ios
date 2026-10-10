# Ollee Shortcuts

Native iPhone companion for the [Ollee Watch](https://www.olleewatch.com/). Pair over Bluetooth, set a 6-character name tag, beep, show a clock-face counter from 0 to 7, and run the same actions from Shortcuts on your phone or Apple Watch. RGB backlight is not in the public command catalogue yet, as described under Light below.

The app surfaces the phone's BLE session through App Intents, so Shortcuts on iPhone or Apple Watch can drive the watch. It is similar in spirit to [Arthur86000/FreeOllee](https://github.com/Arthur86000/FreeOllee), the first open companion for the same hardware, and the Swift here is original rather than a fork or extension of that project or of Super FreeOllee. Frames follow published notes (Nordic UART, CRC-16/CCITT-FALSE, name-tag target `0x2F`) and Gadgetbridge's Ollee work (PR 6411 lineage).

## Credits

- [Arthur86000/FreeOllee](https://github.com/Arthur86000/FreeOllee), the first open companion, thank you
- Ollee Watch by Ollee Technologies Inc.

## Requirements

- iOS 17+, iPhone, Xcode 16
- Close the official Ollee app while you use this one (same Bluetooth radio).
- Signing is Automatic: pick your personal team on the first local run, because no Apple Developer team is configured in the repo.
- Before pairing, turn the watch radio on. On Clock, hold **ALARM**, or tap until **LAP** blinks.

## What the app ships

- Name tag (max 6 ASCII), beep, clock counter 0–7
- App Intents and App Shortcuts so Shortcuts on iPhone or Apple Watch can drive the phone's BLE session
- A Shortcuts recipe in [`Examples/`](Examples/) for notification → clamp 0–7 → clock counter, which you import yourself rather than having the app install automations in the background

Shortcut builders own increment and reset policy, and the app only accepts an integer from 0 to 7.

## Light

RGB/backlight write is not published in the command catalogue used here (Gadgetbridge Ollee support and the FreeOllee-Faces protocol notes), so the UI and the light intent fail closed until a register is confirmed with a golden vector.

## Build

```bash
swift test                          # OlleeFrames, Linux- or macOS-runnable
open OlleeShortcuts.xcodeproj       # iOS app; enable your team to run on a phone
```

There are no third-party Swift package dependencies, and Dependabot watches GitHub Actions only.

## Protocol (short)

Frames on Nordic UART (`6E400001-B5A3-F393-E0A9-E50E24DCCA9E`):

```
00 LEN AA 55 CRC-HI CRC-LO 02 TARGET PAYLOAD…
```

CRC-16/CCITT-FALSE covers `02 TARGET PAYLOAD`, with writes chunked at 20 bytes. Name tag uses `02 2F`. Beep uses alarm-record `playNow` on `02 25` so a new alarm is not persisted. The clock counter writes weekday names on `02 34` while keeping the World Time offset header.
