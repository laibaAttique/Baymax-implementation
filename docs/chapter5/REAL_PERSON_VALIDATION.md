# Module 5: real-person posture validation (status sheet for Chapter 5)

Posture-detection accuracy on real people is a separate kind of evidence from the automated tests:

| Evidence | What it shows | What it does not show |
|---|---|---|
| Synthetic landmark tests (`app/test/atc/atc_m456_*`, `camera_patterns_test.dart`) | Angle maths, phases, rep acceptance, holds, form rules, scoring, feedback timing | Anything about real cameras or bodies |
| Real-photo replay (`real_pose_replay_test.dart`, public-domain dataset photos) | Thresholds work on landmarks of real people (held-out: 66 % reps counted, 13 % false alarms) | Live movement, speed, occlusion, lighting |
| Real-device UI automation (`app/integration_test/`, Flutter integration_test) | The screens, the camera plugin and on-device MediaPipe start, run and stop on the phone; session results reach the plan | Whether reps and corrections are right for a person in front of the camera |
| Real-person validation (this sheet) | Rep counts and corrections for a person actually exercising | — |

Procedure, pass criteria and recording format: [`app/docs/MODULE5_DEVICE_TEST_CHECKLIST.md`](../../app/docs/MODULE5_DEVICE_TEST_CHECKLIST.md).
**Pass** = reps within ±1 per set; each deliberate fault caught on at least 8 of 10 reps; at most 1 wrong correction in 10 correct reps.

| # | Representative exercise | Pattern | Camera set-up | Status | Date / device | Result |
|---|---|---|---|---|---|---|
| 1 | Bodyweight Squat (`squat`) | squat | side-on, whole body | **Partly performed** | 2026-10-15, Redmi Note 11, 1 person | Every rep counted and the back-alignment cue fired on a forward lean (reported by the tester); the full 10-rep checklist with counted faults was not recorded |
| 2 | Push-up (`pushup`) | push-up | side-on, floor level | Not performed | — | — |
| 3 | Lunge (`lunge`) | lunge | side-on | Not performed | — | — |
| 4 | Plank (`plank`) | hold | side-on, floor level | Not performed | — | — |
| 5 | Dumbbell Bicep Curl (`Dumbbell_Bicep_Curl`) | curl | side-on, upper body | Not performed | — | — |
| 6 | Dumbbell Incline Row (`Dumbbell_Incline_Row`) | row | side-on | Not performed | — | — |
| 7 | Dumbbell Shoulder Press (`Dumbbell_Shoulder_Press`) | overhead press | side-on or facing | Not performed | — | — |
| 8 | Glute Bridge (`glute_bridge`) | bridge | side-on, floor level | Not performed | — | — |

Nothing in Chapter 5 claims real-person accuracy for rows 2–8. The real-device UI cases (ATC-DEV-M5-*) were run with nobody
exercising in front of the camera, so their rep counts are not accuracy evidence.
