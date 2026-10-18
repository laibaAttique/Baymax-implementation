# Modules 2 → 4 → 5 integration and posture evaluation expansion — implementation report (2026-10-17)

> **Update 2026-10-18 (at the user's request):** every camera-tracked exercise now works like the validated four —
> reps, FPS, landmarks, live corrections **and a posture score** (same formula), shown on screen, in the summary, saved,
> and read by the voice coach. All 304 tracked exercises have at least one measurable form check (the 50 former
> "basic" ones got one: hips on the bench, hinge-not-squat, straight legs in back extensions, chest-dip lean, knees
> bent in sit-ups and bent-knee raises, still upper body in knee tucks). Counts now: **validated 4 · experimental 300 ·
> basic 0 · unsupported 228**. Non-validated scores are labelled "Posture score (experimental)" until the device
> validation in MODULE5_DEVICE_VALIDATION.md is done; holds score the share of hold time in a correct position.

Related: [MODULE5_CAMERA_PATTERNS.md](MODULE5_CAMERA_PATTERNS.md) (tracker architecture),
[MODULE5_DEVICE_VALIDATION.md](MODULE5_DEVICE_VALIDATION.md) (validation procedure and record),
[review/camera_support_audit.md](review/camera_support_audit.md) / `.csv` / `.json` (generated capability audit),
[MODULE4_PHASE_LEDGER.md](MODULE4_PHASE_LEDGER.md).

## 1. Root causes

| Problem | Cause |
|---|---|
| Only 4 exercises had posture evaluation | Form checks existed only inside the 4 hand-tuned `ExerciseFormRules` configurations; the 22 pattern trackers added earlier had `checks: []`, so they could only count. There were also no measurements for anything but the rep angle, torso lean, a body-line angle and knee tracking. |
| Posture Detection from Home showed generic exercises | The Home tile and the drawer opened `ExercisePickerScreen`, a "temporary test screen" listing the curated library with default doses; it never read the user's plan. |
| Sessions did not update the plan | Sessions were saved without any link to a planned exercise, and Module 4 only had a per-day "Mark done" record (`activity/{date}`), so nothing joined the two. |
| Two exercise sources | Curated library (`ExerciseLibrary`) and dataset catalogue (`ExerciseCatalog`) were looked up separately by each caller. |

## 2. What was built

**Posture evaluation (Phase 3).**
- `PoseAnalyzer` now also measures:
  - knee, elbow and hip angles;
  - the upper-arm angle;
  - the signed hip offset from the shoulder→ankle line (sag vs pike);
  - left/right symmetry (front view);
  - ankle spread (front view).
- The engine adds torso sway relative to the person's own resting posture and the turning-point flag.
- New reusable checks in `form_checks.dart`:
  - `TorsoSwayCheck`
  - `UpperArmStillCheck`
  - `HipLineCheck` (direction-specific cue)
  - `ArmSymmetryCheck`
  - `JointRangeCheck` (any secondary measurement, optionally at the turning point)
- Each check returns "not applicable" when its measurement isn't observable, so a correction is only given after the condition was measured on 3 consecutive frames.
- `MovementPatterns` assigns checks per pattern and per variant:
  - braced curls skip the upper-arm check;
  - one-arm presses skip symmetry;
  - straight-leg hinges and leg raises check the knees;
  - bridges check foot placement.

**Capability levels (Phase 8)** come from `FormEvaluation` on each configuration:
- **validated**: the 4 tuned configurations; form checks, corrections and a posture score.
- **experimental**: real checks and live corrections. There is no numeric score, and the screen, summary, saved session and voice coach all say "experimental, not yet validated".
- **basic**: repetitions or hold time only.
- **unsupported**: a reason is shown and Manual Guidance is offered.

**Coverage (Phase 4):** four new patterns where the movement is clearly visible:

| Pattern | Exercises |
|---|---|
| upright row | 7 dataset exercises |
| single-leg hip extension | kickbacks, bird dog, dead bug |
| plank knee drive | mountain climbers, plank knee drive |
| knee tuck | reverse crunch, leg pull-ins |

A standing hip-flexion exercise also moved to the knee-lift pattern. Exercises where no reliable camera measurement exists stay unsupported, with their reasons.

**Unified catalogue (Phase 2):** `ExerciseRepository` resolves any canonical id to the exercise and its posture config, with no duplicates (dataset entries linked to a curated exercise are hidden). `CatalogEntry.toJson()` gives the normalised record. The original dataset records are unchanged; Baymax metadata sits beside them in `derived`.

**Custom exercises: none added.** Every movement the new checks need already exists in the catalogue (bodyweight squat, lunge, push-up variants, glute bridge, plank, wall sit, curls, presses, and so on). Duplicates would have added nothing, and new exercises would also need MET values from a citable source.

**Personalised Posture Detection (Phase 5):** a new `PostureDetectionHome` replaces the Home tile and drawer target, with three tabs:
- **Today's workout:** today's exercises from the user's own plan.
- **My plan:** the whole week, with rest days shown.
- **Exercise library:** the generic library, kept unchanged.

Each plan entry shows its photo, dose, difficulty, camera capability and whether it's done today. The screen has loading, no-plan and screening-gate states. Starting an exercise passes the exercise id, sets/reps/seconds/rest, movement pattern and safety notes, plus a `PlanLink` (plan fingerprint, weekday, entry index, date). The exercise detail's "Start exercise" passes the same link.

**Completion sync (Phase 6):**
- A session completes its planned exercise only if it reached the target (reps, hold time or manual sets), and never if skipped or only opened.
- `PlanProgress` keys progress by plan fingerprint + day + date, so a regenerated plan starts fresh and repeat sessions create nothing twice.
- When every main exercise of today's plan day is done, the day is marked through the same `ActivityService.markDone` as "Mark done". That is what the fitness score, streaks, badges and analytics read.
- Progress is read back from today's saved sessions after a restart.
- The workout tab and Posture Detection show "Done today".
- Library sessions stay independent.

**Safety (Phase 7):** unchanged order: classification → rules → eligibility → plan → posture. The posture layer only reads plans. A 300-person test checks every scheduled exercise passes the rules, and that a camera-tracked exercise the rules exclude (jump squats at BMI 30+) is never scheduled.

## 3. Numbers

| | Count |
|---|---|
| Unified catalogue (73 curated + 816 dataset not duplicating a curated exercise) | 889 |
| Schedulable exercises (curated + dataset for any owned equipment, within the program rule) | 532 |
| Validated posture evaluation | 4 |
| Experimental posture evaluation | 250 |
| Basic tracking only | 50 (all repetitions) |
| Not reliably supported | 228 |
| New movement patterns | 4 (26 in total: 24 repetition, 2 hold) |
| New custom exercises | 0 |

Before this change: 4 / 0 / 284 / 244.

Unsupported by reason:
- small movements: 85
- multi-phase jumps/throws: 41
- twists: 30
- stretches: 29
- no tracker yet (e.g. ab rollouts, straight-arm pulldowns): 27
- machine cardio: 9
- walking/stepping: 6
- fast alternating: 1

Basic-only, because no reliable camera check was found for them:
- chest presses on a bench (39)
- some hinges, hyperextensions, dips, a bent-knee leg raise
- sit-ups and knee tucks

## 4. Status

| Item | Status |
|---|---|
| Today's workout | done, tested (widget tests with the real generated plan) |
| Complete workout plan | done, tested |
| Generic exercise library | kept, tested |
| Completion sync | done, tested (unit + widget). **Plan link in saved sessions needs the database rules deploy** (5 new optional fields in `workoutSessions`, dry-run valid). Until then the app saves the session without the link and today's progress still works in the running app. |
| Automated tests | 866 pass, 13 skipped, 0 fail |
| Real-device testing | **only the squat (2026-10-15)**. All experimental configurations are untested on a device; see the validation procedure. Synthetic tests are not evidence of real-world accuracy. |

## 5. Scoring

The validated posture score is unchanged:
- **Score** = 100 × acceptable reps ÷ attempted reps.
- **Acceptable rep:** it reached the configured depth, and every check that could be assessed passed on at least `repPassRate` (0.8) of that rep's valid frames.
- **Accuracy** = passed ÷ assessed check-frames, shown only after `minFramesForAccuracy` (15) assessed frames.
- Both constants are in `posture_engine.dart`.

Experimental configurations compute the same per-check tallies for the summary ("passed / failed in N of M reps"), but no score is shown until the configuration is validated.

## 6. Remaining limitations

- Every experimental threshold is a team-chosen starting value (`movement_patterns.dart`, `form_checks.dart`), not validated on people, and not a clinical criterion.
- Some measurements only work from a specific camera position. The front-view checks (symmetry, foot spread, knee tracking) report "not applicable" in side view and vice versa.
- Bench and machine exercises may be partly hidden by the equipment.
- The plan link depends on the rules deploy (above).
