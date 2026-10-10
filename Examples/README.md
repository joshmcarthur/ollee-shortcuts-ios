# Notification to clock counter

This recipe is a starting point for notification → clamp 0–7 → clock counter, which you import yourself rather than having the app install automations in the background. Shortcut builders own the app list, increment, and reset policy, and the app only accepts an integer from 0 to 7.

On iOS 27 a shared shortcut can include a Notification automation. You still tap Import and pick the apps, and the Gallery will not publish this recipe.

## What it does

1. Runs when a notification arrives from apps you pick.
2. Reads the last count (a Shortcuts variable, default 0).
3. Adds 1, then clamps to 0–7 (`min(7, n)`).
4. Runs **Set Ollee clock counter** with that integer.

Reset is another shortcut that sets the counter to 0, or a time-of-day automation.

## Build it in Shortcuts

1. Open Shortcuts → Automation → New → **When a notification is received** (iOS 27), or a personal automation you already use for notifications.
2. Choose the apps that should move the shade/count, and leave the rest unchecked unless you want every banner to tick the watch.
3. Add **Get Variable** / **Set Variable** named `OlleeCount` (Number, default 0).
4. Add **Calculate**: `OlleeCount + 1`.
5. Add **Calculate**: `Minimum` of that result and `7`.
6. Add **Set Ollee clock counter** (from this app) with the clamped number.
7. Add **Set Variable** `OlleeCount` to the clamped number so the next notification continues from there.

The same intent is in the App Shortcuts list the in-app Shortcuts link opens. You can run **Set Ollee clock counter** by itself to test pairing (0 through 7) before wiring notifications.

## Action list

[`notification-to-clock-counter.json`](notification-to-clock-counter.json) is the action list in one file. Apple does not let this repo drop a signed `.shortcut` into your library, so rebuild from the JSON or the steps above.

Close the official Ollee app while you test. On Clock, hold **ALARM**, or tap until **LAP** blinks, so the radio is on.
