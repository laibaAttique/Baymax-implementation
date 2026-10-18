# Module 5 — validation record for camera posture evaluation

All 304 camera-tracked exercises run the same pipeline: MediaPipe Pose Landmarker (33 landmarks, on-device) → joint
angles → rep counter / hold timer → form checks → live corrections → posture score. The app shows them all the same
way. This file records how far each movement pattern has been **validated on real people**. The app adds one small
note under the score ("Form feedback for this movement hasn't been validated on real users yet.") for every pattern that
is not fully validated. Nothing is called validated unless this file says so.

Status values, strongest first:
- **validated**: passed the live checklist ([MODULE5_DEVICE_TEST_CHECKLIST.md](MODULE5_DEVICE_TEST_CHECKLIST.md)) with a real person moving in front of the phone.
- **tuned**: an original Module 5 configuration, with thresholds set on real movements; only partly recorded.
- **real-photo checked**: thresholds calibrated and checked on real people's photos (section 2). This covers rep coverage and false alarms on correct form, but **not** whether a real mistake triggers the correction, nor tracking at speed.
- **not yet tested**.

Synthetic tests (`test/posture_evaluation_test.dart`, `test/camera_patterns_test.dart`) check the logic only and are
never counted as validation.

## 1. Per-pattern record

| Pattern | Tracked exercises | Camera position | Checks (live corrections) | Status | Test conditions | Observed accuracy | Known limitations |
|---|---|---|---|---|---|---|---|
| Squat — curated `squat`, `chair_squat` | 2 | side-on, 2–3 m | back alignment (≤ 60° lean), knee tracking (front view), depth | **tuned**; squat live-tested | 2026-10-15, Redmi Note 11, indoor, 1 person | every rep counted; back-alignment cue fired on forward lean; ~14 FPS | full checklist not yet run; the real photos show standing knees at 146–165° (the tuned config needs ≥ 160°) |
| Push-up — curated `pushup`, `knee_pushup` | 2 | floor level, side-on | body line, depth | **tuned** | not separately recorded | — | record a live session |
| Squat — dataset variants | 24 | side-on | back alignment (≤ 70°), knee tracking (≥ 0.6, front view), range | **real-photo checked** | 23 real photo pairs | 78 % reps counted, 13 % false alarms (held-out 90 % / 0 %) | barbell/rack may hide the knees |
| Biceps curl | 49 | side-on, upper body | upper arm still (≤ 55°, free curls), torso sway (≤ 20°), range | **real-photo checked** | 46 pairs | 65 % counted, 13 % false alarms (held-out 54 % / 8 %) | alternating curls can't form a rep from two photos (fine live); braced curls skip the upper-arm check |
| Chest press | 39 | side-on | torso sway (hips on bench, ≤ 10°), range | **real-photo checked** | 30 pairs | 60 % counted, 10 % false alarms | lying poses and the bar can hide the elbows |
| Overhead press | 33 | side-on (lean) / facing (symmetry) | lean back (≤ 20°), arm symmetry (≤ 40°, two-arm only), range; a hanging arm is ignored | **real-photo checked** | 30 pairs | 83 % counted, 7 % false alarms | Bradford/Cuban presses barely change the elbow angle |
| Row | 27 | side-on | torso sway (≤ 20°), range | **real-photo checked** | 27 pairs | 67 % counted, 7 % false alarms | cable/machine may hide the arm |
| Triceps extension | 27 | side-on | torso sway (≤ 12°) | not yet tested (photos: 55 % counted, 0 % false alarms) | 22 pairs | below the 60 % bar | photos often show a partial range |
| Arm raise | 18 | facing | arms almost straight (elbow ≥ 120°), sway (≤ 14°) | not yet tested (photos: 67 % / 17 %) | 18 pairs | false alarms above the 15 % bar | front raises are better seen side-on |
| Lunge | 11 | side-on | torso upright (≤ 30°), range | **real-photo checked** | 8 pairs | 62 % counted, 12 % false alarms | rear knee may be hidden; small sample |
| Hip hinge | 10 | side-on | straight-leg: knee ≥ 120°; others: knee ≥ 70° at the bottom | not yet tested (photos: 100 % / 20 %) | 10 pairs | false alarms above the bar | spine curve not visible from 3 torso points |
| Triceps pushdown / kickback | 10 | side-on | upper arm still (≤ 50°), sway (≤ 12°) | not yet tested (photos: 60 % / 40 %) | 10 pairs | upper-arm check too strict on photos | cable stack may hide the hands |
| Vertical pull | 7 | side-on | torso sway (≤ 20°) | **real-photo checked** | 7 pairs | 71 % counted, 14 % false alarms | small sample |
| Upright row | 7 | facing | torso sway (≤ 15°) | **real-photo checked** | 7 pairs | 71 % counted, 0 % false alarms | small sample |
| Glute bridge / hip extension | 5 | floor level, side-on | bridge: foot position (knee 60–125° at top); back extension: straight legs | not yet tested (4 pairs) | — | — | lying poses are harder for MediaPipe |
| Leg curl, leg extension, dip, single-leg hip extension, knee tuck, knee lift, plank knee drive, push-up (dataset) | 2–4 each | see the audit | see the audit | not yet tested (1–3 photo pairs each) | — | — | too few real photos |
| Jumping jack, plank hold, wall sit, sit-up | 1–2 each | facing / floor | see the audit | not yet tested (no usable photo pairs) | — | — | — |

## 2. Real-photo validation (2026-10-18)

**Method.**
- **Data:** free-exercise-db (Unlicense) has two photos of a real person for most exercises: the start and end position. The photos come from the pinned commit `f00c92c`.
- **Landmarks:**
  - The app's own model, `pose_landmarker_lite.task`, ran **on the phone** (Redmi Note 11, Android 13, video mode, production native bridge) for 280 exercises, recording angles; see `integration_test/dataset_pose_validation_test.dart`.
  - The same model file then ran **on the PC** through MediaPipe Python in still-image mode, recording full landmarks for 269 exercises with both photos usable; see `ml/validation/pc_pose_landmarks.py`.
  - Phone vs PC rep angles differed by a median of 6° (68 % within 10°, 90th percentile 26°). The phone halves the image and runs in video mode.
- **Replay:** the landmarks are stored in `test/fixtures/real_poses.json` and replayed through the production analyzer and engine on every `flutter test` run (`test/real_pose_replay_test.dart`). For each pair it checks:
  - that one photo is at rest and the other past the turning point;
  - that the engine counts exactly one rep for rest → end → rest;
  - which checks fire on the (correct) demonstrated form.
- **Calibration:** exercises were split deterministically in half. Thresholds were set on the calibration half only (`ml/validation/calibrate_thresholds.py`): each rep threshold covers about 85 % of real start/end photos, using whichever of PC or phone angles was stricter, and each check covers about 90 % of correct demonstrations, with caps so every check still catches a clear fault. The **held-out half** is used for reporting and as the regression gate.

**Results (non-validated patterns only; the 4 tuned configurations were not changed):**

| | Before calibration | After calibration |
|---|---|---|
| Held-out: reps counted | 24 % | **66 %** |
| Held-out: any false alarm on correct form | 31 % | **13 %** |
| Calibration half: reps counted / false alarms | 24 % / 25 % | 69 % / 10 % |

The two halves agree, so the thresholds are not fitted to the data they are reported on. Gate in
`real_pose_replay_test.dart`: held-out reps counted ≥ 60 % and false alarms ≤ 18 %, or the build fails.
Full per-pattern and per-exercise results: `review/real_pose_validation.md` / `.json`.

**What this does not show.** Whether a real *mistake* triggers its correction (sensitivity), tracking during fast
movement, and the effect of the user's own room, light and clothing. Those still need the live checklist.

Changes made from this data:
- Every rep threshold of the non-validated patterns.
- Check limits:
  - curl: upper arm 35° → 55°, sway 10° → 20°;
  - press: lean 15° → 20°, symmetry 25° → 40°;
  - row sway 15° → 20°;
  - pushdown upper arm 35° → 50°;
  - raise: elbow 130° → 120°, sway 12° → 14°;
  - squat: lean 60° → 70°, knee ratio 0.65 → 0.6;
  - hinge knees 130° / 80° → 120° / 70°.
- One-arm presses now ignore the hanging arm (it was being tracked instead of the pressing arm).

## 3. Exercise-specific records

| Exercise (id) | Pattern | Date | Device | Participants | Camera position, light | Reps (counted / observed) | Corrections (true / false) | Result | Notes |
|---|---|---|---|---|---|---|---|---|---|
| Bodyweight Squat (`squat`) | squat | 2026-10-15 | Redmi Note 11 | 1 | side-on, indoor | every rep counted (user-confirmed) | back-alignment cue fired on forward lean (user-confirmed) | tuned, partly recorded | full checklist not yet run |

Per-exercise real-photo results are in `review/real_pose_validation.json` (angles, rep counted, false alarms, checks not
applicable from that camera angle).

## 4. Promoting a pattern

When a pattern passes the live checklist:
1. Fill in its row above: status **validated**, test conditions and observed accuracy.
2. In `lib/services/posture/movement_patterns.dart`, set that pattern's configuration to `FormEvaluation.validated`. This removes the small note in the app; nothing else changes.
3. Run `flutter test`, then regenerate the reports:

   ```
   BAYMAX_WRITE_REVIEW=1 flutter test test/camera_support_report_test.dart test/real_pose_replay_test.dart
   ```

To re-run the real-photo validation on the phone:

```
flutter test integration_test/dataset_pose_validation_test.dart -d <device>
```

Then rebuild the fixture with `ml/validation/extract_real_poses.py`.
