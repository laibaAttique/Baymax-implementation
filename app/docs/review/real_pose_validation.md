# Real-pose validation (generated)

two real photos per exercise (start/end); production MediaPipe landmarks replayed through the production engine; thresholds tuned on the calibration half, reported on the held-out half.

Source: free-exercise-db photos (Unlicense), commit f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5; landmarks from pose_landmarker_lite on a Redmi Note 11 (Android 13).

| Split | Pairs | Rep counted | Any false alarm on correct form |
|---|---|---|---|
| calibration | 136 | 69% | 10% |
| heldOut | 120 | 66% | 13% |

## Held-out half, by movement pattern

| Pattern | Pairs | Rep counted / in position | False alarms on correct form |
|---|---|---|---|
| row | 16 | 75% | sway 6% |
| legCurl | 1 | 100% | sway 100% |
| curl | 26 | 54% | sway 8% |
| squat | 10 | 90% | none |
| benchPress | 10 | 80% | sway 10% |
| overheadPress | 13 | 69% | torso 15% |
| tricepsPushdown | 4 | 50% | upper_arm 50% |
| tricepsExtension | 11 | 64% | none |
| armRaise | 7 | 57% | arms_straight 14%, sway 14% |
| dip | 2 | 50% | none |
| pulldown | 3 | 67% | sway 33% |
| singleLegExtension | 2 | 0% | none |
| hipExtension | 3 | 33% | legs_straight 33% |
| legExtension | 1 | 100% | none |
| hinge | 6 | 100% | knees_soft 33% |
| lunge | 2 | 0% | torso 50% |
| plankKneeDrive | 1 | 0% | none |
| uprightRow | 2 | 100% | none |

Static photos only: fault sensitivity (does a real mistake trigger the correction?) and tracking at speed still need the live checklist (MODULE5_DEVICE_TEST_CHECKLIST.md).
