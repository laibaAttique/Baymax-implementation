# Module 5 — validation record for camera posture evaluation

All 304 camera-tracked exercises run the same pipeline: MediaPipe Pose Landmarker (33 landmarks, on-device) → joint
angles → rep counter / hold timer → form checks → live corrections → posture score. The app shows them all the same
way. Whether a movement pattern's checks have been **validated on a real person with a real phone** is recorded here,
and the app adds one small note ("Form feedback for this movement hasn't been validated on real users yet.") under the
score for patterns that have not. Nothing is called validated in the app or in the report unless this file says so.

- Synthetic tests (`test/posture_evaluation_test.dart`, `test/camera_patterns_test.dart`) prove each check reacts to
  the intended geometry. They are **not** evidence of accuracy on real people and are not recorded as validation here.
- Per-exercise capability: `review/camera_support_audit.csv` / `.json` (pattern, checks, required landmarks).
- How to test: [MODULE5_DEVICE_TEST_CHECKLIST.md](MODULE5_DEVICE_TEST_CHECKLIST.md).

Status values: **validated** (passed the checklist, recorded below) · **tuned** (original Module 5 configuration,
thresholds set on real movements, only partly recorded) · **not yet tested**.

## 1. Per-pattern record

An exercise's status is its pattern's status unless section 2 has an exercise-specific entry.

| Pattern | Tracked exercises | Camera position | Checks (live corrections) | Status | Test conditions | Observed accuracy | Known limitations |
|---|---|---|---|---|---|---|---|
| Squat — curated `squat`, `chair_squat` | 2 | side-on, 2–3 m | back alignment (≤ 60° lean), knee tracking (front view), depth | **tuned**; squat device-tested | 2026-10-15, Redmi Note 11, Android 13, indoor light, 1 person | reps counted on every rep; "keep your back straight" fired when leaning too far forward; ~14 FPS | knee tracking needs a front view; not tested with several people |
| Squat — dataset variants | 24 | side-on | back alignment, knee tracking | not yet tested | — | — | barbell/rack can hide the knees; back-squat lean is naturally larger |
| Push-up — curated `pushup`, `knee_pushup` | 2 | floor level, side-on | body line, depth | **tuned** | not separately recorded | — | record a session to confirm |
| Push-up — other variants | 7 | floor level, side-on | hip position (sag / pike) | not yet tested | — | — | wall and incline push-ups are near-vertical, so the hip check does not apply |
| Biceps curl | 49 | side-on, upper body | upper arm still (≤ 35°), torso stability (≤ 10° sway), range | not yet tested | — | — | braced curls (preacher, incline) skip the upper-arm check; the far arm is often hidden side-on |
| Chest press | 39 | side-on | torso stability (hips on bench, ≤ 10°) | not yet tested | — | — | bench and bar can hide the elbows |
| Overhead press | 33 | side-on (lean) or facing (symmetry) | back alignment (≤ 15° lean), arm symmetry (≤ 25°, facing only) | not yet tested | — | — | symmetry needs a front view; lean needs a side view |
| Row | 27 | side-on | torso stability (≤ 15°) | not yet tested | — | — | cable/machine may hide the arm |
| Triceps extension | 27 | side-on | torso stability (≤ 12°) | not yet tested | — | — | overhead variants put the wrists above the frame edge |
| Arm raise | 18 | facing | arms almost straight (elbow ≥ 130°), torso stability (≤ 12°) | not yet tested | — | — | front raises are better seen side-on |
| Lunge | 11 | side-on | torso upright (≤ 30° lean), range | not yet tested | — | — | the rear knee may be hidden |
| Hip hinge | 10 | side-on | straight-leg variants: knees ≥ 130°; others: no squatting (knee ≥ 80° at the bottom) | not yet tested | — | — | the spine's curve is not visible from 3 torso points |
| Triceps pushdown / kickback | 10 | side-on | upper arm still (≤ 35°), torso stability | not yet tested | — | — | cable stack may hide the hands |
| Vertical pull | 7 | side-on | torso stability (≤ 20°) | not yet tested | — | — | pull-ups need the bar in frame |
| Upright row | 7 | facing | torso stability (≤ 12°) | not yet tested | — | — | — |
| Glute bridge / hip extension | 5 | floor level, side-on | bridges: foot position (knee 60–125° at the top); back extensions: straight legs | not yet tested | — | — | lying poses are harder for MediaPipe |
| Leg curl | 4 | side-on | torso stability | not yet tested | — | — | machine pads hide the legs |
| Single-leg hip extension (kickback, bird dog, dead bug) | 4 | floor level, side-on | torso stability (≤ 15°) | not yet tested | — | — | alternating sides |
| Knee lift (march, high knees) | 3 | side-on | stand tall (≤ 20° lean) | not yet tested | — | — | fast high knees at ~15 FPS |
| Leg raise | 2 | floor level, side-on | straight legs (≥ 145°) or knees near 90° (bent-knee) | not yet tested | — | — | — |
| Dip | 2 | side-on | torso lean (≤ 30° triceps, ≤ 45° chest) | not yet tested | — | — | — |
| Knee tuck | 2 | floor level, side-on | torso stability | not yet tested | — | — | — |
| Jumping jack | 2 | facing | feet wide at the top (ankles ≥ 1.5 × hip width) | not yet tested | — | — | fast movement at ~15 FPS |
| Plank hold | 2 | floor level, side-on | hip position (sag > 6 % / pike > 10 % of body length) | not yet tested | — | — | loose clothing hides the hips |
| Leg extension | 2 | side-on | torso stability | not yet tested | — | — | machine hides the shins |
| Plank knee drive (mountain climbers) | 2 | floor level, side-on | stay low (torso lean ≥ 50°) | not yet tested | — | — | fast alternating legs |
| Wall sit | 1 | side-on | knee angle 70–120°, back on the wall (≤ 35° lean) | not yet tested | — | — | — |
| Sit-up | 0 scheduled | floor level, side-on | knees bent (40–130°) | not yet tested | — | — | — |

## 2. Exercise-specific records

Add a row when a particular exercise is tested (it overrides its pattern's status for that exercise only).

| Exercise (id) | Pattern | Date | Device | Participants | Camera position, light | Reps (counted / observed) | Corrections (true / false) | Result | Notes |
|---|---|---|---|---|---|---|---|---|---|
| Bodyweight Squat (`squat`) | squat | 2026-10-15 | Redmi Note 11 | 1 | side-on, indoor | every rep counted (user-confirmed) | back-alignment cue fired on forward lean (user-confirmed) | tuned, partly recorded | full checklist not yet run |

## 3. Promoting a pattern

When a pattern passes the checklist:
1. Fill in its row above: status **validated**, test conditions and observed accuracy.
2. In `lib/services/posture/movement_patterns.dart`, set that pattern's configuration to `FormEvaluation.validated`. This removes the small note in the app; nothing else changes.
3. Run `flutter test`, then regenerate the audit:

   ```
   BAYMAX_WRITE_REVIEW=1 flutter test test/camera_support_report_test.dart
   ```

If thresholds are tuned from the logged angles, note the values before and after in the "Known limitations" cell.
