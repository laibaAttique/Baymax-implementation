# Module 4 phase ledger

Single source of truth for where Module 4 (knowledge-based workout generation) stands. Update the row and add a log line
whenever a phase changes state. Plan: [MODULE4_KB_IMPLEMENTATION_PLAN.md](MODULE4_KB_IMPLEMENTATION_PLAN.md).

Status values: **done** (implemented + tests green) · **verified** (also checked live / on device) · **in progress** ·
**planned** · **blocked**. Nothing is marked done without the evidence column filled in.

## Current state — 2026-10-17

| Phase | Scope | Status | Evidence |
|---|---|---|---|
| F1 | Import free-exercise-db at pinned commit, validate, keep dataset fields unchanged | done | `build_catalog.py --check` up to date; module4_test "Dataset import" group; commit ceba697 |
| F2 | 2024 Compendium MET mapping (27 verbatim activities, 181/606/84) | done | module4_test "MET mapping" group (published-value check) |
| F3 | Safety rule repository rules-2026.10.1 + engine (5 outcomes, most-restrictive merge) | done | workout_rules_test (incl. 3,000-person Module 3 oracle) |
| F4 | Readiness screening (symptoms, clearance, injuries, equipment) + gate | done | module4_test "Safety in generated plans"; screens_test cardiac gate |
| F5 | Generator integration on Aamna's engine, ranking reasons, rule notes, snapshot (FNV-1a) | done | module4_test determinism + snapshot tests |
| F6 | UI: workout tab, exercise detail (photos, MET, notes), readiness screen, Module 5 hand-off | done | screens_test, atc_functional_test ATC-M4-F01/F02 |
| F7 | Merge Aamna's bd8a2a1 (specialist plans, consultation split) without losing either side | done | commit d787933; specialist plans respect the gate (`specialist_plan_apply.dart`) |
| F8 | RTDB rules: friend's file + 4 Baymax sections (workoutSessions, exerciseFeedback, workoutReadiness, workoutPlan) | verified | deployed 2026-10-17 after confirmation; live = local; 166 friend paths unchanged; anonymous read 401; backups in `firebase-rules-backups/` |
| F9 | Data intact after the rules incident | verified | user EF4Sgw… still has 9 sessions + 1 feedback; only writes had been refused |
| K1 | Dataset analysis; fix D1 (wrist joints) and D5 (stale docstring) | done | plan §1; 58 wrist-tagged entries; test "hand-supported and forearm exercises…" |
| K2 | Intensity band on every exercise (WHO bands on the Compendium MET) | done | `Exercise.intensityBand`; module4_profiles_test "K2" (counts 134/528/125/84 equal plan §1.4) |
| K3 | Classification profiles (6 categories) + 3 profile notes; `riskLevel` / `statisticalRisk` facts | done | `classification_profiles.dart`; module4_profiles_test "K3" |
| K4 | Band cap in the engine; unknown intensity not scheduled under a cap | done | module4_profiles_test "K4" incl. 3,000-person property test; workout_rules_test oracle unchanged |
| K5 | Weekly structure: Diabetic rest-day limit, aerobic/strength/stretching tallies, walking suggestion | done | module4_profiles_test "K5" |
| K6 | "Your training profile" card, band on exercise detail, adaptations in Module 5 screens | done | module4_profiles_test "K6" + "Module 4 → Module 5" widget tests |
| K7 | Versions: `rules-2026.10.1+profiles-2026.10.1`, engine `workout-engine-2026.10.2`; no DB rule change, nothing to deploy | done | module4_test snapshot test |
| K8 | Review sheet for a qualified professional | done | `docs/review/module4_review_sheet.csv` (65 entries); review_sheet_test fails when it is stale |
| K9 | Device verification of Module 4 screens and the Module 5 hand-off | **blocked** (B1) | — |
| K10 | Docs, PROGRESS.md, capability → code → test table | done | `MODULE4_WORKOUT_KNOWLEDGE_BASE.md` §4a, §6a, §6b |

## Needs you (external / your decision)

| Id | What | Why it cannot be done here |
|---|---|---|
| X1 | Free space on C: (or close VS Code + Antigravity) so the Android build can run, then test on the phone (K9) | B1; your files and editors |
| X2 | A qualified reviewer (physiotherapist / exercise physiologist / doctor) fills in the review sheet | the project team cannot approve its own medical rules |
| X3 | Push branch `Laiba-Attique` | pushing is yours |

## Blockers

| Id | Blocker | Cause (measured) | What unblocks it |
|---|---|---|---|
| B1 | `flutter build apk` fails: "Gradle build daemon disappeared unexpectedly" | JVM out of memory (`hs_err_pid35216.log`: mmap of 490 MB failed). Commit charge 24.9 / 27.0 GB, 1.4 GB RAM free, C: has 0.04 GB free so the page file cannot grow. The VS Code and Antigravity Java language servers hold ~2 GB each. | Free several GB on C: and/or close VS Code + Antigravity during the build. Owner: user. |

## Shared files touched outside Laiba's modules (for teammates)

| File | Owner | Change | Why |
|---|---|---|---|
| `lib/services/plan_generator.dart`, `exercise_selector.dart` | Aamna | readiness + rule engine + catalogue pool; old `_restrictions` replaced by the repository (oracle-tested identical) | Module 4 requirement, chosen "extend her engine" |
| `lib/services/user_session.dart` | shared | merged both versions; basePlan → specialist overlay | merge d787933 |
| `lib/services/specialist_plan_apply.dart` | Aamna | specialist workout applied only when `workoutAvailable`; gate + rulesVersion kept; the specialist week gets a profile summary | a specialist plan must not bypass the screening gate |
| `lib/models/workout_session.dart`, `posture_mode.dart`, `manual_guidance.dart` | Laiba (Module 5) | `SessionExercise.safetyNotes`, "Adapted for you" card | Module 4 adaptations must reach the session |
| `lib/screens/profile/settings_screen.dart` | Aamna | section content wrapped in a transparent `Material` | fixed a ListTile assertion that failed community_test |
| `database.rules.json` | shared | 4 sections added before `$other`; nothing of the friend's removed | F8 |

## Log

- 2026-10-17 — F1–F7 committed (ceba697, d787933). Full suite: 766 pass, 13 skipped, 0 fail.
- 2026-10-17 — F8 merged rules deployed after explicit confirmation; verified live = local. F9 data checked.
- 2026-10-17 — B1 diagnosed (out of memory, not disk or code).
- 2026-10-17 — K1: dataset profiled; wrist derivation added to the importer, catalogue rebuilt (MET counts unchanged:
  181/606/84, 871 imported), regression test added. Module 4 tests: 43 pass; full suite 767 pass, 13 skipped, 0 fail.
- 2026-10-17 — K2–K8, K10 implemented: intensity bands, classification profiles + notes, band cap, Diabetic rest-day
  limit, weekly tallies, profile card, Module 5 safety notes, review sheet. Module 4 profile tests: 19 pass. Full suite:
  787 pass, 13 skipped, 0 fail (TEMP on D:, `--concurrency=2`). K9 still blocked by B1.
- 2026-10-17 — Module 5 integration: camera tracking by movement pattern for every schedulable exercise (4 full, 281
  basic reps, 3 basic hold, 244 not supported with reasons). See `docs/MODULE5_CAMERA_PATTERNS.md`. Full suite 829 pass.
