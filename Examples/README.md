# Notification → clock counter (import this yourself)

Free Ollee 2 does not silently install Shortcuts automations. This recipe is a starting point for a **Shortcuts builder**. You own the app list, increment, and reset policy. The app only accepts an integer 0–7.

On iOS 27 a shared shortcut can include a Notification automation; you still tap Import and pick apps. The Gallery will not publish this for us.

## What it does

1. Runs when a notification arrives from apps you pick.
2. Reads the last count (a Shortcuts variable, default 0).
3. Adds 1, then clamps to 0…7 (`min(7, n)`).
4. Runs **Set Ollee clock counter** with that integer.

Reset is yours: another shortcut that sets the counter to 0, or a time-of-day automation.

## Build it in Shortcuts

1. Open Shortcuts → Automation → New → **When a notification is received** (iOS 27) or a personal automation you already use for notifications.
2. Choose the apps that should move the shade/count. Do not select everything if you do not want every banner to tick the watch.
3. Add **Get Variable** / **Set Variable** named `OlleeCount` (Number, default 0).
4. Add **Calculate**: `OlleeCount + 1`.
5. Add **Calculate**: `Minimum` of that result and `7`.
6. Add **Set Ollee clock counter** (from Free Ollee 2) with the clamped number.
7. Add **Set Variable** `OlleeCount` to the clamped number so the next notification continues from there.

The same building-block intent is also in the App Shortcuts list the in-app Shortcuts link opens — you can run **Set Ollee clock counter** by itself to test pairing (0 through 7) before wiring notifications.

## Reference graph

See [`notification-to-clock-counter.json`](notification-to-clock-counter.json) for the action list in one file. Apple does not let this repo drop a signed `.shortcut` into your library; rebuild from the JSON or the steps above.

Close the official Ollee app while testing. Hold **ALARM** on Clock, or tap until **LAP** blinks, so the radio is on.
