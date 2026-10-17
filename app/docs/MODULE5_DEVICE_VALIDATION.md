# Module 5 — real-device validation of posture evaluation

Synthetic tests (`test/posture_evaluation_test.dart`, `test/camera_patterns_test.dart`) prove that every check
measures and reacts to the intended landmark geometry. They are **not** evidence that MediaPipe's landmarks on a real
person, camera and room are good enough. That needs the procedure below. An experimental configuration is promoted to
**validated** (posture score shown) only after it passes it.

## What has actually been tested on a device

| Exercise | Date | Device | Who | Result | Level |
|---|---|---|---|---|---|
| Bodyweight squat (`squat`) | 2026-10-15 | Redmi Note 11, Android 13 | project member (user) | skeleton aligned with the body; rep counter increased on each rep; "Keep your back straight" triggered when leaning too far forward; ~14 FPS after tuning | validated |
| Chair squat, push-up, knee push-up | — | — | — | not separately recorded on a device | validated level kept from the original Module 5 tuning; **record a session to confirm** |
| All experimental and basic configurations | — | — | — | **not tested on a device yet** | experimental / basic |

Nothing else in this document is a result. Do not report experimental checks as validated until the table above has an
entry for them.

## Procedure (per movement pattern)

Equipment: the phone on a stand at the stated camera position (`setupHint`), good light, plain background. Debug build
(`flutter run` or the debug APK), with `adb logcat -s flutter` capturing the `[pose]` lines (angles, phases, reps, cues
— numbers only, never images).

1. **Consent.** Participants agree to being filmed only by the phone's live preview; nothing is stored (the app keeps no
   frames). Record participant id, height range and clothing, not names.
2. **Correct form, 2 × 10 reps** (or 2 × 30 s holds). Observer counts reps and notes any genuine faults.
   - Pass if the counted reps equal the observer's count (±1 per set) and no correction fires on more than 1 rep in 10
     the observer judged correct (false-positive rate ≤ 10 %).
3. **Deliberate faults, 1 × 10 reps per check** (e.g. swinging the upper arm in a curl, leaning back in a press, sagging
   hips in a plank, feet together in a jumping jack).
   - Pass if the matching correction fires on at least 8 of 10 faulty reps (sensitivity ≥ 80 %) within about 1 s.
4. **Camera problems.** Step partly out of frame; turn the wrong way. Pass if the app names the missing body parts or
   asks to reposition, and counts nothing while landmarks are missing.
5. Repeat with at least **3 participants** of different builds.
6. Write the result in the table above (date, device, participants, counts), and only then change the configuration's
   `evaluation` to `FormEvaluation.validated` in `movement_patterns.dart` (or move it into `ExerciseFormRules`).
   Re-run `flutter test` and regenerate the audit (`BAYMAX_WRITE_REVIEW=1 flutter test test/camera_support_report_test.dart`).

Thresholds may be tuned from the logged angles during this procedure; any change must be noted here with the values
before and after.

## Suggested order (most-used first)

squat (dataset variants) → push-up variants → lunge → plank → glute bridge → biceps curl → overhead press →
lateral raise → row → jumping jack → the rest.
