# Baymax real-device UI automation (Modules 4, 5, 6)

Appium 3 + the UiAutomator2 driver, driven by WebdriverIO (Mocha), against the installed Baymax app (`com.example.app`) on a USB-connected
Android phone. Selectors use the accessibility labels that Flutter exposes as the Android content-description; no screen coordinates.

| Spec | Cases | What it covers |
|---|---|---|
| `tests/module4_workout.e2e.js` | ATC-M4-A01..A03 | Today's workout card, weekly plan, exercise detail |
| `tests/module5_posture.e2e.js` | ATC-M5-A01..A04 | Posture home tabs, mode selection and consent, camera notice, manual guidance |
| `tests/module6_voice.e2e.js` | ATC-M6-A01..A03 | Voice assistant state, close button, chatbot (Module 13) is a separate screen |
| `tests/cross_module.e2e.js` | ATC-INT-A01..A02 | Plan → posture session (4→5), session → voice coach (5→6) |

These cases check navigation and what the screens show. They do **not** prove pose-detection, rep-counting or speech-recognition accuracy.

## Run

```bash
cd automation/appium
npm install
ANDROID_HOME=D:/android-sdk npx wdio run ./wdio.conf.js
```

Prerequisites: the phone is connected with USB debugging (`adb devices` lists it), the app is installed and **signed in** (the suite never
types credentials and never clears app data), JDK 17+ on `JAVA_HOME`. Override the device with `BAYMAX_UDID`.

Outputs: `reports/junit/*.xml` (JUnit), `reports/appium_results.jsonl` (one line per case: Passed / Failed / Blocked with the observed text),
`screenshots/<case id>.png`, `reports/wdio-appium.log` (server log). The 2026-10-18 run logs are kept as `reports/*-2026-10-18.txt`.

## Status on the test phone (Redmi Note 11, Android 13, MIUI), 2026-10-18: Blocked

The run reached the phone, but the UiAutomator2 driver stopped at its standard start-up step
`settings put global hidden_api_policy 1`: MIUI answered `SecurityException: ... requires android.permission.WRITE_SECURE_SETTINGS`.
Taps are refused for the same reason (`adb shell input tap` → `Injecting input events requires ... INJECT_EVENTS`). No setting was changed and
no Appium package was left on the phone. The evidence is in `reports/` (JUnit XML, server log, wdio log). `reports/appium_results.jsonl`
records the 12 cases as Blocked with that reason.

To unblock (phone owner only): Settings → Additional settings → Developer options → enable **USB debugging (Security settings)**
(MIUI asks for a Mi account sign-in). Be aware that Appium then temporarily relaxes the Android hidden-API policy during each session and
restores it at the end, and installs its two UiAutomator2 server apps (`io.appium.uiautomator2.server*`). Then re-run the command above;
the suite needs no change.
