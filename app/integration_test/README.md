# Real-device integration tests (Modules 4, 5, 6)

Flutter's official `integration_test` package runs the real Baymax app on a USB-connected Android phone and operates it
automatically (taps, scrolls, navigation go through Flutter's gesture system; no Android input injection, no Appium).

| File | Cases | Covers |
|---|---|---|
| `smoke_test.dart` | ATC-DEV-S01 | App shell starts, bottom navigation to Workout and back |
| `module4_workout_test.dart` | ATC-DEV-M4-01..07 | Weekly plan, day selection, exercise detail, regenerate, training profile, symptom gate, no profile |
| `module5_posture_test.dart` | ATC-DEV-M5-01..09 | Posture home tabs, today / my plan / library, consent, live camera session + Stop + summary, manual guidance, camera denied, unsupported exercise |
| `module6_voice_test.dart` | ATC-DEV-M6-01..04 | Voice assistant from the chatbot, microphone state, chip replies with real TTS, plan-aware reply, close |
| `cross_module_test.dart` | ATC-DEV-INT-01..03 | Plan → session → recorded completion; voice inside a live camera session; voice "Pause workout" |
| `all_device_test.dart` | all of the above | One install for everything |
| `dataset_pose_validation_test.dart`, `pose_benchmark_test.dart` | — | Earlier on-device pose checks (unchanged) |

## Controlled test session (no real account is touched)

- A fictional user ("Device Tester") is put into the in-memory `UserSession`; nobody signs in.
- Firebase is initialised (the shell needs it) but with no signed-in user every read/write of user data is denied by the rules.
  If an account **is** signed in on the installed build, every case stops as **Blocked** instead of using it.
- Finished sessions go to an in-memory log (`MemoryWorkoutLog`), never to the cloud.
- Permissions: `DevicePermissions` reads the phone's real camera/microphone permission but never shows the Android dialog
  (a Flutter test cannot answer it). The camera-denied case simulates the answer inside the app.

## Run

```bash
cd app
bash integration_test/run_on_device.sh integration_test/smoke_test.dart my_smoke_run
```

```bash
bash integration_test/run_on_device.sh integration_test/all_device_test.dart my_full_run
```

Evidence: `docs/chapter5/device_evidence/<run>/` — `flutter_drive.log` (one `[device-case] {json}` line per case, plus every step),
`device.txt` (model, Android version, command, Flutter version, times), `device_results.json`, `screenshots/`.

**Read the result from the device runner**, i.e. the `I/flutter … +N -M: All tests passed! / Some tests failed.` line and the
`[device-case]` records — the host driver's own "All tests passed." line was observed to be wrong once.

### Important on the phone (MIUI)

- `run_on_device.sh` passes `--keep-app-running`. Without it, `flutter drive` **uninstalls the app** at the end, which deletes the
  phone's local app data (sign-in).
- MIUI shows an "Install via USB" prompt; if it is not confirmed, the first install fails (`INSTALL_FAILED_USER_RESTRICTED`) and
  Flutter **uninstalls and reinstalls**, which also clears the app's local data.
- After testing, the phone has the *test* build installed. Reinstall the normal app:

```bash
flutter build apk --debug
```

```bash
adb -s f3fd6781 install -r build/app/outputs/flutter-apk/app-debug.apk
```

## Limits

- Camera cases run with nobody in front of the camera: they prove the camera + MediaPipe pipeline starts, runs and stops on the
  device, not posture accuracy. Real-person validation: `docs/chapter5/REAL_PERSON_VALIDATION.md`.
- Voice cases use the phone's real speech and TTS engines with fixed chip phrases; nothing is spoken to the phone, so they do not
  validate speech-recognition accuracy.
- Cloud saving is not exercised (no account); the offline message is asserted instead.
