# Module 5 — camera tracking for generated workout exercises

## Root cause (before 2026-10-17)

Camera Detection was enabled by `ExerciseFormRules.supports(exerciseId)`, a fixed map of **four curated ids**
(`squat`, `chair_squat`, `pushup`, `knee_pushup`). `PostureModeSelection` greyed the card out for every other id, and
`CameraDetection` threw if opened for one. So:

- every free-exercise-db exercise added by Module 4 (ids such as `Dumbbell_Bicep_Curl`) was excluded, even when it was
  the same movement as a supported one (`Pushups` vs `pushup`);
- 69 of the 73 curated exercises were excluded, including planks and lunges;
- there was no notion of a movement pattern, no static-hold tracking, and no reason shown to the user.

Of the 532 exercises the generator can schedule, 4 had camera tracking.

## Architecture now

```
free-exercise-db record ──► ml/exercise_catalog/movement_patterns.py ──► derived.movement {pattern, reason, rule}
curated exercise ─────────► lib/models/movement_pattern.dart (curatedMovements / curatedNoTracking, by hand)
                                   │
Exercise.movement ─► SessionExercise.movement (WorkoutSessionRequest.fromPlanned, Module 4 → 5)
                                   │
                MovementPatterns.forSession()  (lib/services/posture/movement_patterns.dart)
                     │ id has tested form rules? ──► fullForm (ExerciseFormRules, unchanged)
                     │ pattern has a tracker?   ──► basicTracking (reps) / holdTracking (time)
                     └ otherwise                ──► notSupported + reason shown to the user
                                   │
          PostureEngine ─ RepCounter (closing or opening movements) / HoldTracker (holds)
```

- Patterns are keyed by **stable ids** (dataset `id`, curated `id`); names are used only at import time, together with
  the dataset's category/force/muscle fields, and every result records the rule that produced it.
- Patterns are about the **movement**, not the muscle: `Barbell_Squat` and `Leg_Extensions` both train the quadriceps
  but are `squat` and `legExtension`.
- `ExercisePostureConfig` (exerciseId, movementPattern, level, requiredLandmarks, form, unsupportedReason, and the
  `supportsCameraTracking / RepCounting / FormEvaluation / HoldTiming` flags) is what the screens use.

## Support levels

| Level | What the user gets | Where |
|---|---|---|
| Full posture evaluation | reps, posture checks, posture score, accuracy, live corrections | the 4 configurations tuned on real movements |
| Basic camera tracking (repetitions) | reps counted from the movement cycle, live phase cues, "Form is not scored" label; no posture score | every exercise with a rep pattern |
| Basic camera tracking (hold time) | time counted only while in position (plank body line + torso near horizontal; wall-sit knee angle + upright back) | planks, wall sit |
| Not reliably supported | Camera card disabled **with the reason**; Manual Guidance | stretches, machine cardio, travelling, small movements (wrists, calves, crunches, flyes), twists, multi-phase jumps/throws, fast alternating floor moves |

Basic tracking never shows a posture score, accuracy or "too shallow" verdicts, on screen, in the summary, in the saved
session, or from the voice coach ("the camera only counts your repetitions; it doesn't judge your form").

## Trackers

`RepCounter` (unchanged state machine: hysteresis, smoothing, outlier rejection, minimum rep time, tracking timeout)
now also counts **opening** movements (rest bent → peak open: overhead press, arm raise, bridge, pushdown, leg
extension, jumping jack) by running on the mirrored angle 360° − θ. `AngleAggregate.furthest` lets the moving limb drive
one-arm and alternating exercises.

| Pattern | Angle | Rest → turn (°) | Direction |
|---|---|---|---|
| squat | hip–knee–ankle | ≥160 → ≤100 | bend |
| lunge | knee (furthest) | ≥160 → ≤110 | bend |
| hinge | shoulder–hip–knee | ≥160 → ≤120 | bend |
| hipExtension | shoulder–hip–knee | ≤145 → ≥165 | open |
| pushup / benchPress / dip | shoulder–elbow–wrist | ≥150–155 → ≤95–105 | bend |
| overheadPress / tricepsPushdown | elbow (furthest) | ≤110 → ≥150–155 | open |
| armRaise | hip–shoulder–elbow (furthest) | ≤35 → ≥75 | open |
| row / pulldown / tricepsExtension | elbow (furthest) | ≥150 → ≤95–100 | bend |
| curl | elbow (furthest) | ≥150 → ≤70 | bend |
| legExtension / legCurl | knee (furthest) | ≤110 → ≥155 / ≥150 → ≤100 | open / bend |
| sitUp / legRaise | shoulder–hip–knee | ≥115 → ≤80 / ≥150 → ≤110 | bend |
| kneeLift | shoulder–hip–knee (furthest) | ≥160 → ≤125 | bend |
| jumpingJack | hip–shoulder–elbow | ≤40 → ≥120 | open |
| plankHold | shoulder–hip–ankle (knee for knee planks) | in position: ≥155 (150), torso lean ≥50° (45°) | hold |
| wallSitHold | hip–knee–ankle | in position: 70–120, torso lean ≤35° | hold |

**These angles only detect movement phases.** They are team-chosen starting values from the usual range of each
movement, not validated on test subjects and not form or medical criteria — which is why these levels report no score.

## Camera workflow

Mode selection resolves the config → consent → camera permission (refusal offers Manual Guidance) → `CameraDetection`
→ MediaPipe landmarks → required landmarks checked; missing ones are named ("Can't see your knees and ankles — stand
side-on …") → tracker → live metrics that the level actually provides → stop → summary → saved with the existing
`workoutSessions` schema (hold time goes in the feedback text; no database rule change).

## Audit

`docs/review/camera_support_audit.md` / `.csv`, generated by `test/camera_support_report_test.dart` from the code:
532 schedulable exercises — 4 full posture evaluation, 281 basic repetition tracking, 3 basic hold tracking,
244 not reliably supported (each with its reason). Manual Guidance is available for all 532.

## Tests

`test/camera_patterns_test.dart`: Dart/Python pattern lists identical; every catalogue entry has a pattern; spot checks
by stable id; every curated exercise mapped or explained; only the 4 tuned ids get full scoring; the hand-off carries
the pattern; **each of the 20 rep patterns counts 3 synthetic cycles and rejects a partial one**; opening movements do
not count a rep when starting at the peak; one-arm curls; plank and wall-sit hold timing (glitch tolerance, sagging,
leaving the frame); missing-landmark guidance; voice coach answers; screens: dataset exercise opens Camera Detection,
basic tracking counts and saves, plank hold saves, unsupported exercise explains and keeps Manual Guidance, permission
refusal. Existing posture, voice and screen tests unchanged except the one that asserted a plank could not use the camera.

## Limitations

- Basic tracking thresholds are not validated on people; real-device tuning (as was done for the squat) is still needed
  per pattern. Machine and bench exercises need a side view that the equipment may partly block.
- Synthetic poses test the logic end to end, but not MediaPipe's accuracy for each exercise.
- Alternating patterns (knee lift) count every lift; one-arm patterns count the moving arm.
