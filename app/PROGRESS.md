# Baymax — Implementation Progress & Change Log

Living document. Every change to the codebase, every decision, and every module's status gets recorded here.
Source of truth for requirements: `Baymax_Scope(006,019,022).docx` (FE/FR IDs below refer to it).

- **Project:** Baymax — AI-Driven Adaptive Fitness & Health Monitoring System (COMSATS Islamabad, supervisor Dr. Memoona Malik)
- **Team:** Aamna Rasheed Khan, Laiba Attique, Laiba Zahoor
- **Mobile app:** Flutter, `app/` · **Backend scaffold:** Node/Express/Mongoose in `../Baymax-main` · **Mockups:** `../Baymax-main/mockups` (S-01 … S-39)
- **Phase target:** 60% of scope, ~1 month of work starting 2026-10-09

---

## 1. Focus modules (60% target)

| # | Module | Scope-doc owner | Mockups | Status |
|---|--------|-----------------|---------|--------|
| 1 | User Authentication & Health Profiling | Laiba Zahoor | S-01..S-07, S-38 | 🟡 Built; needs console setup + device test; at-rest encryption pending |
| 2 | AI Health Classification Engine | Aamna | S-08 | 🟡 Rules + trained Logistic Regression (hybrid) integrated and tested; AUC 0.73–0.76; JSON in app, TFLite exported & verified |
| 3 | Intelligent Personalized Plan Generator | Laiba Zahoor | S-10, S-11, S-39 | 🟡 Plans built & tested; FR-4 calorie optimisation done as an **adaptive energy-balance algorithm** (not Gradient Boosting, which needs IAEA doubly-labelled-water data released on request); rules for the weight log awaiting deploy |
| 7 | Smart Diet & Calorie Tracking | Laiba Attique | S-19..S-22 | 🟡 Text logging built & tested; photo recognition trained (22 foods, 92.6% test top-1) and integrated as **experimental** — failed the per-class gate on aloo gobi/paratha, so release builds don't use it; not run on a device |
| 8 | Allergy & Ingredient Scanner | Laiba Attique | S-23, S-24 | 🟡 Built & tested; OCR needs a Google Vision key |
| 12 | AI Chatbot | Aamna | S-30 (+ S-31 for doctor referral) | 🟡 Rule-based bot built & tested; answers from the user's own logs (food, workouts, weigh-ins, streaks). Dialogflow deliberately not used |
| 11 | Community Ranking & Gamification | (not in the focus list) | — | 🟡 Score, badges, levels, opt-in leaderboard built & tested (FR-1,2,3,5); K-Means only with 15+ users; scores not tamper-proof; not run on a device |
| 14 | Secure Data Management & Smart Alerts | (not in the focus list) | — | 🟡 Roles, workout reminders, inactivity alerts done (FR-2,3,5); **AES, injury alerts, FCM push not done** |

Legend: 🔴 not started · 🟡 in progress / partial · 🟢 done & verified

> **Open question:** the brief says "9 modules for now" but names six (1, 2, 3, 7, 8, 12). The other three are not yet identified here — add them to the table above once confirmed.

---

## 2. Change log

### 2026-10-22 — Nutrition plan: Regenerate meals, your own calories, and logging the plan

Requested: a way to change a nutrition plan you do not like, to set it by your own calories, and to log it.
- **Regenerate meals** (`UserSession.regenerateMeals`): another set of meals for the same calories; the workouts are untouched (the generator now takes a separate `mealVariant`). Tested: new sets differ for several kinds of people and the exercise list is identical.
- **Set my calories** (`UserSession.setCustomKcal`, `services/meal_plan_prefs.dart`): the plan, macros and meals are rebuilt for the member's own daily target. Allowed range: not below the safe floor (larger of BMR and 1,500 kcal men / 1,200 women, the same floor as the recommended target), at most 1,000 below and 500 above maintenance (the same limits as the body forecast). Anything outside is refused with a reason (never silently used); the generator also clamps. "Use recommended" goes back. A member following a specialist's diet plan is told to switch to Baymax's plan first (the specialist's calories win).
- **Logging:** "Log this meal" on each meal card and "Log my whole day": one food-log entry per food with the plan's servings and nutrition (source `manual`, an allowed value), Undo for 30 seconds, and a "Log again?" question if the meal was already logged from this plan today.
- **Stored** at `users/{uid}/mealPlan` ({variant, customKcal}). Rule added to `database.rules.json` and `api/emulator/database.rules.json` and **deployed to `baymax-148da` on 2026-10-22 with the owner's OK** (not yet tried from a signed-in phone).
- Found and fixed a real bug on the way (the calorie dialog disposed its text field while still on screen); the dialog is now its own widget.
- Tests: `test/meal_plan_choices_test.dart` (14). Whole merged suite 1,069 pass in the temp copy (camera and speech_to_text relaxed); not run on a phone. Built in `Baymax-implementation/app`; not copied into the older `untitled folder/app`.

### 2026-10-22 — Module 17: Weekly Report, Progress Tracker and Workout History (built on the merged tree)

Requested: complete the remaining Module 17 parts. Built in `Baymax-implementation/app` (it has the merged workout-session data); NOT copied into the older `untitled folder/app` working folder.
- **FR-7 Weekly Report and FE-10 weekly/monthly analytics** (`screens/analytics/progress_screens.dart`, `services/activity_reports.dart`): This week / Last week / Last 30 days; workouts done of planned, active minutes, calories eaten per day, fitness score (weeks only) with the change from the week before, form score from camera sessions, weight change, days logged; a written summary and one "focus". **The summary is produced by fixed rules from the user's own numbers, not by an AI model, and the screen says so** (the scope says "AI-generated"). It never praises eating far below the calorie target and says so in plain words. "Copy this report" (clipboard).
- **FR-9 Workout History:** 12-week calendar heatmap (Monday first, five shades by minutes, future days empty, tap a day to see only it) and one card per workout day with its exercises, reps, minutes and form scores; a day recorded only as "workout done" is listed too.
- **FR-8 Progress Tracker:** weight chart with the target line, body measurements log (waist, chest, hips, arm, thigh in cm, any subset, checked 10 to 300 cm, change from first to latest). **Progress photo upload is NOT built:** it needs a storage service (firebase_storage or path_provider) that is not in the project and was not approved.
- Analytics now links to all three screens. The injury-risk trend is still missing (no injury-risk module).
- **Database rules:** new `users/{uid}/measurements/{date}` node in `database.rules.json` and `api/emulator/database.rules.json`. **Deployed to `baymax-148da` on 2026-10-22 with the owner's OK** (the same merged rules file that carries the Module 4 to 6 and chat nodes). Not yet tried from a signed-in phone.
- **Tests:** `test/progress_reports_test.dart` (21): period maths, counts, averages, summary wording and the low-intake warning, heatmap shades and layout, history grouping, measurement checks, and the three screens. Found and fixed a real crash (heatmap opacity above 1.0) and layout overflows.
- **Verification of the merged tree:** the merged `pubspec.yaml` needs a newer Flutter SDK than this Mac has (camera 0.12.1 and speech_to_text 7.5.0 need Dart 3.12). In a temp copy with those two relaxed (camera ^0.11.2, speech_to_text ^7.4.0) and the sibling `backend/dialogflow` folder present, the whole merged suite passes: 1,055 tests, 7 skipped (the dictionary-dependent ones, because the repo carries a placeholder dictionary). Not run on a phone.

### 2026-10-22 — Module 11 (Predictive Body Transformation): forecast, milestones and the two screens (energy-balance model; Gradient Boosting NOT built)

Requested: complete Module 11. Built `services/body_forecast.dart` and `screens/analytics/transform_forecast_screens.dart`; `BodyTransformScreen` is now the hub (offers "Predict my results", keeps the weigh-in trend).
- **FR30 input screen:** calorie deficit or surplus (whole number, 0 to 1,000 or 0 to 500), workouts a week (2 to 5), optional goal text ("Lose 7 kg" is read as a target), the consistency note, "Predict My Results".
- **FR31 result screen:** editable summary cards and an "Adjust inputs" panel that recomputes live, predicted weight and fat change after 30 days with body fat % (estimate), a chart (planned path, a path if only 60% is followed, goal line, milestone dots), milestones with dates, safety notes, "Copy My Forecast" (clipboard: no sharing package was added), the method.
- **Model:** daily energy balance. Expenditure falls 100 kJ (23.9 kcal) per kg lost and energy per kg is 39.5 MJ fat / 7.6 MJ lean (Hall et al., Lancet 2011, read from the paper); lean share of a change = 10.4/(10.4 + fat mass) (Hall, Br J Nutr 2007: Forbes relation, read from the paper); starting fat from BMI, age, sex (Deurenberg 1991, SEE 4.1 points). Intake never goes below the same safe floor as the calorie target; no deficit for BMI under 18.5. One workout = 3 kcal per kg net (estimate, 5 METs for 45 min).
- **Checks (tests):** no change in diet = no change in weight; a 500 kcal deficit loses 1.5 to 3 kg in 30 days, mostly fat; more deficit or exercise loses more; loss slows down; weight heads for deficit/23.9 kg below the start; a fatter person loses a larger share as fat; floors, underweight, limits; milestone ordering; unreachable and wrong-direction targets.
- **Gradient Boosting is NOT built, on purpose.** WEEE (Zenodo 6420886) holds energy expenditure during activities for 17 people, not weight changes, so it cannot train this (as already noted for Module 3); no dataset of weight trajectories under known deficits is available. A model trained on this simulator's own output would only copy the simulator. The Sources screen and the result screen say "not a trained model". If the supervisor requires Gradient Boosting, the honest options are real longitudinal data or labelling it a surrogate of this model.
- Not modelled: water and glycogen, adherence, medicines and conditions. Not validated against anyone's real weight loss. Flutter 677 tests pass (21 new in `test/body_forecast_test.dart`). Not run on a device.

### 2026-10-22 — Allergen dictionary (Module 10) and meal plans drawn from all food datasets

Requested: a dataset for allergies, implemented; and the nutrition plan from all datasets, not only the 97 curated foods.

**Allergen dataset.** Downloaded (with the user's request as the go-ahead) the Open Food Facts `allergens.txt` and `food/ingredients.txt` taxonomies (3 MB) into `ml/data/openfoodfacts/` (git-ignored). `ml/allergen_data/build_allergen_terms.py` turns them into `assets/data/allergen_terms.json` (52 KB): 1,818 ingredient names with their allergens (dairy 559, fish 299, gluten 314, nuts 171, shellfish 160, soy 111, eggs 110, sesame 37, peanuts 36, plus celery, mustard, lupin, sulphites), 24 "not dairy" phrases (coconut milk, cocoa butter) and 105 words the team added (naan, roti, dahi, mayonnaise ...), counted separately. Allergens are inherited down the ingredient graph (cheddar below cheese below milk). **Licence of the two taxonomy files not confirmed** (repo is AGPL-3.0, the Open Food Facts database ODbL): the file must not go into the public GitHub repo until checked (same rule as `foods_bulk.json`); the Sources screen cites Open Food Facts.
- Scanner: `AllergenMatcher` asks the dictionary first (longest phrase wins: soy milk is soy, peanut butter is peanuts and nuts, coconut milk is not dairy), then the old word lists and fuzzy matching; a warning from any step is kept. Profile allergy choices now include Peanuts, Fish and Sesame.
- Foods: the allergens of every food (also the 2,700 searchable ones) get the dictionary's findings added to their stored list (it only adds; 119 foods gained at least one). Still estimates, and the app says so.
- **Still needs:** the Google Vision key for photo scanning (pasting the ingredient text works without it); no on-device OCR package was added.

**Meal plans from all datasets.** `services/meal_roles.dart` decides, from name, serving and numbers, whether and where a dataset food can appear in a plan: 1,105 of the 2,857 foods qualify (curated 97, team list 294, Indian Nutrient Databank 496, USDA 218). Refused: raw meat, fish and eggs, offal and skin, dry grains and pulses (also by energy density), oils, sauces, sugar, spices, supplements, baby food, pork and alcohol, serving under 25 g or in spoonfuls, and numbers that contradict themselves (energy not within 30% of 4P+4C+9F, a serving with over 90 g fat, more nutrients than food). `PlanGenerator._buildMeal` picks, for each role, among the 12 foods whose serving best fits that role's share of the meal's calories (plus protein richness for a main dish when losing weight or gaining muscle), rotated by the plan variant; 12 variants of one profile used 127 different foods from all four sources. The diabetic, hypertension and heart filters apply to the dataset foods through name-based tags.
- **Allergy policy (errs toward warning):** a person with any allergy gets only curated foods, single USDA foods, and fruit and vegetables from the lists; recipe dishes from the team list and the Indian table are left out because a dish name does not reveal its ingredients.
- **Limits:** none of the lists has sodium, sugar or fibre, so the health tags are guessed from the name; recipe-based values are averages; roles are rules, not hand review. Nutrition screen shows each item's source and a note.
- Tests: Flutter 656 pass (new `test/allergen_dictionary_test.dart` 13, `test/meal_plan_datasets_test.dart` 13); `flutter analyze` on the touched files: info-level notes only. Not run on a device.
- **Not synced to `Baymax-implementation`:** its `plan_generator.dart` and `sources_screen.dart` have diverged from this folder (the merged workout work), so these changes need a careful merge, not a copy.

### 2026-10-22 — Web: checks everywhere, payments, video room and chat (portal, admin panel, API, app)

Requested: put proper checks in all the web dashboards, finish the payment and video parts, and build chat. Phase 2 (specialists editing user plans) was not touched.

**Checks (API, portal, admin)**
- API (`baymax-api/src/lib/validate.js`, `limiter.js`): ids in addresses are validated (400 before Firebase is touched), query values must make sense (a bad status or date range is a 400 instead of being ignored), bodies must be JSON objects sent as JSON (415), 120 writes a minute per signed-in person, 20 chat messages a minute per conversation (429). Changed behaviour: `GET /appointments?status=weird` is now 400.
- Portal and admin: field-by-field checks beside each field (login, register, registration form, profile, new-specialist form, diet and workout plan editors, refund reason, chat message), character counters, unsaved-changes warning on the profile, 20-second request timeout, a session that ends mid-use returns to sign-in with a message, error and not-found pages, CSV export neutralises spreadsheet formulas, approving a registration asks for confirmation.
- Layout fix: wide tables no longer stretch the page.

**Payments (Module 15 on the web)**: specialist Payments page (earned, upcoming, waiting, pay-at-clinic, due, refunded; filters; CSV); admin Payments page (totals, platform fees, per-specialist figures, refund with a reason). Refunds are recorded on `appointments/{id}/refund` (the `payment` record is never rewritten): automatic on decline, specialist cancel, account closing and an expired unanswered request; a patient who cancels is refunded by the administrator. Test gateway only: a live payment is marked `manual`.

**Video**: in-portal call room (`/appointments/:id/call`): device check, Jitsi inside the page, join/leave log (`callLog`), notes beside the call, mark completed afterwards. The room name is given out only inside the join window and only for a room on the configured server. **Not verified:** the Jitsi service itself (needs internet and a camera): only the pre-join screen was checked in a browser.

**Chat**: patient app screen (`consultation_chat_screen.dart`, `consultation_chat.dart`), portal Messages (list, thread, unread counts, polled every 4 s), API routes, rules `chats` and `chatRead` (patient writes only own plain-text messages, 1 to 1000 characters, to an accepted appointment until 24 h after the slot). Specialist overview now shows four role-specific cards (FR10.3, FR11.3, FR12.3); cards needing AI-engine data are still not shown.

**Tests**: API 178 pass (was 142); emulator end-to-end all files pass (rules 14, flow 10, admin-account 3, money-and-messages 4, new); Flutter 630 pass in total including 12 new in `test/consultation_chat_test.dart`; `flutter analyze` on the touched files reports only info-level style notes; both web apps build. Browser walkthrough on the emulators: login checks, role overview, payments, messages (sent a reply), call pre-join, admin refund (with and without a reason).

**Not done / needs the owner**
- Rules: the new `chats` and `chatRead` nodes were **deployed to `baymax-148da` on 2026-10-22 with the owner's OK**, from the merged snapshot copy (`Baymax-implementation/app/database.rules.json`, which also carries the Module 4 to 6 nodes, so nothing of Laiba's was removed). The chat rules were tested on the emulator only; never exercised against the real project from a signed-in phone.
- The API on port 4000 and the web dev servers that were already running must be restarted to pick up this code.
- Test-case report (`Baymax_Test_Cases`) was not regenerated; `e2e_cases.json` has entries for ATC-INT-34..40. No new Dart ATC cases were written for the chat screen.
- Not pushed to GitHub.

### 2026-10-19 — Viva guide (audit of the merged project, no project file changed)
`~/Downloads/Baymax_Viva_Guide/FYP_Complete_Technical_Analysis_and_Viva_Guide.docx` (26 sections, 7 diagrams, 36 algorithms, AI/ML audit, Firebase audit, viva Q&A) built by `Baymax_Viva_Guide/build/build_guide.py`. Findings recorded there: live-rules snapshot of 2026-10-17 lacks the Module 4-6 nodes; legacy unauthenticated `POST /api/profile` and `GET /api/profile/:id` in `Baymax-main`; ml/README still says MobileNetV2 (model is EfficientNetV2-B0); all 27 safety rules pending review; merged app not run by the auditor.

### 2026-10-17 — Pushed to GitHub
Commit `bd8a2a1` on `Amna's-work` (branch `main` untouched): `app/`, new `api/`, `portal/` (web only) and `admin/` folders (the old `portal/server`+`web` layout was replaced), `docs/` (Chapters 4 and 5). Left out: all `.env*` files (only `.env.example` is published), Firebase client config, the food model, `foods_bulk.json`, `CLAUDE.md`, raw console logs with local paths; registration numbers removed from the pushed copy of this file.

### 2026-10-16 — Chapter 5 test cases for the 60% milestone (`~/Downloads/Baymax_Test_Cases/`)
289 automated test cases with unique IDs (`ATC-M<module>-U|F|B<nn>`, `ATC-INT-<nn>`), all passing, for the modules the user chose (merged numbering 1, 2, 3, 4, 8, 9, 12, 13, 14, 16, 17; Module 10 removed at the user's request): 105 unit, 73 functional, 84 business-rule, 27 integration. The document now holds the test cases and their traceability only, no explanatory text. Module 3 (Home) cases added 2026-10-16 (13). Cases for Modules 10, 11 and 15 stay in the code as regression tests but are filtered out of the report by `INCLUDED` in `generate_report.py`.
Code: `app/test/atc/` (helper + 4 Dart suites, 241 cases), `baymax-api/test/atc/` (66 API cases), IDs added to the titles of the existing emulator tests in `baymax-api/e2e/` (24 cases).
`Baymax_Test_Cases/tools/run_all.sh` runs everything (starts the emulators itself; e2e files must run one at a time) and `generate_report.py` builds the Chapter 5 `.docx` (template styles, 5.1-5.5, RTM),
the CSVs and Figure 5.1 from the real run output (`ATC_LOG` JSON lines + the e2e JUnit XML). A case with an ID in the code but no result shows as "Not run".
Full suites after the change: `flutter test` 605 pass (364 + 241), `npm test` 142 pass.
Requirement IDs follow the merged report. Module 14 FR-11..15 and Module 12 FR-10 are requirements added during the build and are not in Chapter 2 (marked "added" in the RTM); the report's second "FR-6" in Module 2 is treated as FR-7.
Not covered and not claimed: anything on a physical phone, OCR with the Vision key, the food photo model, screens' appearance, a browser walkthrough of the portals, real payments (test gateway). 67 of 105 listed requirements have an automated case.
Found while writing the cases: nothing in the app failed; the only defects were in the new test code itself (a wrong expectation for the moving average, ID collisions caught by the generator).


Newest first. Format: date · what changed · files · why.

### 2026-10-18 — Posture thresholds calibrated on real people (free-exercise-db photos)

- New on-device test `integration_test/dataset_pose_validation_test.dart`: the app's own MediaPipe model and engine on the Redmi Note 11, applied to the two real photos (start/end) of 280 camera-tracked exercises. Person detected in both photos for 94–100 % per pattern. Before calibration only 24 % of real rep pairs were countable and 31 % of correct demonstrations triggered a false correction.
- Same model file on the PC (MediaPipe Python, isolated venv on D:) to store landmarks for 269 exercises → `test/fixtures/real_poses.json`, replayed through the production engine on every `flutter test` (`test/real_pose_replay_test.dart`). Phone vs PC angles: median 6° apart.
- Thresholds of the non-validated patterns calibrated on half the exercises (`ml/validation/calibrate_thresholds.py`), reported on the other half: **reps counted 24 % → 66 %, false alarms 31 % → 13 %** (calibration half 69 % / 10 %). One-arm presses now ignore the hanging arm. Regression gate: held-out ≥ 60 % counted, ≤ 18 % false alarms.
- 8 patterns marked "real-photo checked" in `docs/MODULE5_DEVICE_VALIDATION.md` (squat variants, curl, chest press, overhead press, row, lunge, vertical pull, upright row). The in-app note stays until live validation (fault sensitivity, speed).
- The 4 tuned configurations were not changed. Tests: 867 pass, 13 skipped, 0 fail.
- **Side effect:** the on-device test run uninstalled the Baymax app from the phone (MIUI blocked the reinstall without a tap); data is in Firebase; reinstall needs one tap on the phone.

### 2026-10-18 — One consistent camera experience; validation record and test checklist

- The prominent "experimental" wording was removed: all 304 camera exercises show the same description, "Posture score" and corrections as the validated four. Untested patterns get one small note under the score ("Form feedback for this movement hasn't been validated on real users yet."), in the session summary and a short sentence from the voice coach. Nothing untested is called validated.
- Pipeline, rep counting, scoring and corrections unchanged; Module 4 untouched.
- Docs: `docs/MODULE5_DEVICE_VALIDATION.md` (per-pattern and per-exercise records: conditions, camera position, observed accuracy, limitations) and `docs/MODULE5_DEVICE_TEST_CHECKLIST.md` (8 major patterns, step by step, pass criteria).
- Tests: 866 pass, 13 skipped, 0 fail.

### 2026-10-18 — Posture score for every camera exercise

- At the user's request every camera-tracked exercise now behaves like the validated four: reps, FPS, landmarks, live corrections and a posture score (same formula: acceptable reps ÷ attempts; holds: share of hold time in a correct position), on screen, in the summary, saved to `workoutSessions`, and from the voice coach.
- The 50 rep-only exercises got measurable checks, so all 304 tracked exercises run form checks: validated 4, experimental 300, unsupported 228 (Manual Guidance with the reason).
- Scores that are not device-validated are labelled "Posture score (experimental)".
- Tests: 866 pass, 13 skipped, 0 fail.

### 2026-10-17 — Modules 4 + 5: real posture evaluation, personalised Posture Detection, plan completion sync

Report: `docs/MODULE4_5_INTEGRATION_REPORT.md`; validation procedure: `docs/MODULE5_DEVICE_VALIDATION.md`; audit: `docs/review/camera_support_audit.{md,csv,json}`.

- **Posture evaluation:** new measurements (secondary joint angles, upper-arm angle, signed hip offset, arm symmetry, foot spread, torso sway from the person's own starting posture) and reusable checks (`form_checks.dart`), assigned per pattern and variant. Capability levels: validated 4 (unchanged, score shown) · experimental 250 (real checks + live corrections, clearly labelled, no score) · basic 50 · unsupported 228 (with reasons). 4 new patterns (upright row, single-leg hip extension, plank knee drive, knee tuck). No custom exercises were needed.
- **Unified catalogue:** `ExerciseRepository` (889 exercises, canonical ids, no duplicates, normalised `CatalogEntry`).
- **Posture Detection home** (Home tile + drawer): Today's workout / My plan / Exercise library; loading, no-plan and screening states; entries start with a plan link.
- **Completion sync:** sessions that reach their target complete the planned exercise (`PlanProgress`); a fully completed day is marked through the existing `ActivityService.markDone` (feeds fitness score, streaks, badges, analytics); "Done today" in the workout tab and Posture Detection; no duplicates; regenerated plans start fresh; library sessions stay independent.
- **Database rules:** 5 optional plan fields added to `workoutSessions` in `database.rules.json` (dry run valid, only additions vs live). Deployed 2026-10-17 after confirmation; live rules verified identical to the local file, anonymous read still 401.
- **Safety:** unchanged order; a test checks camera capability never makes an exercise eligible.
- **Tests:** 866 pass, 13 skipped, 0 fail. New `posture_evaluation_test.dart` (18), `plan_integration_test.dart` (15).
- **Device testing:** none for the new checks (phone disconnected); only the squat has a recorded device test (2026-10-15).

### 2026-10-17 — Module 5: camera tracking for generated exercises (movement patterns)

Write-up: `docs/MODULE5_CAMERA_PATTERNS.md`; audit: `docs/review/camera_support_audit.md` / `.csv`.

- **Root cause:** Camera Detection was a fixed list of 4 curated ids (`ExerciseFormRules.supports`); every dataset exercise and 69 curated ones were greyed out. 4 of the 532 schedulable exercises had camera tracking.
- **Movement patterns:** every exercise now has one (stable-id based): dataset ones from `ml/exercise_catalog/movement_patterns.py` at import (`derived.movement`, rule id recorded), curated ones by hand in `lib/models/movement_pattern.dart`. The pattern travels with the exercise from Module 4 to Module 5.
- **Trackers:** `MovementPatterns` maps 20 rep patterns and 2 hold patterns to tracker configs; `RepCounter` now also counts opening movements (presses, raises, bridges); new `HoldTracker` times planks and wall sits only while in position. The 4 tuned configurations keep full form scoring, unchanged.
- **Levels:** 4 full posture evaluation, 281 basic repetition tracking, 3 basic hold tracking, 244 not reliably supported (each shows its reason; Manual Guidance always available). Basic tracking shows and saves no posture score, accuracy or "too shallow" verdict; the voice coach says form is not judged.
- **Guidance:** missing landmarks are named ("Can't see your knees and ankles — …").
- **Storage:** unchanged `workoutSessions` schema; no database rule change.
- **Tests:** full suite 829 pass, 13 skipped, 0 fail. New `test/camera_patterns_test.dart` (39 + voice) and `test/camera_support_report_test.dart`; one old test that asserted a plank could not use the camera now uses calf raises.
- **Not verified:** basic-tracking thresholds on real people (only synthetic poses); needs device testing per pattern.

### 2026-10-17 — Module 4: training profiles from the Module 2 classification (ledger K2–K8, K10)

Ledger: `docs/MODULE4_PHASE_LEDGER.md`; design: `docs/MODULE4_KB_IMPLEMENTATION_PLAN.md`; write-up: `docs/MODULE4_WORKOUT_KNOWLEDGE_BASE.md` §4a, §6a, §6b.

- **Intensity bands:** every exercise gets a WHO 2020 band (light < 3 / moderate 3–5.9 / vigorous ≥ 6 MET) from its Compendium MET only. Catalogue: 134 light, 528 moderate, 125 vigorous, 84 without a value.
- **Classification profiles** (`lib/services/workout_rules/classification_profiles.dart`, `profiles-2026.10.1`, pending review): one per Module 2 category. Moderate cap for Obese, At-Risk and Cardiac (team precaution); WHO weekly targets (150–300 aerobic min, 2+ strength, 2+ stretching days); Diabetic: no more than 2 rest days in a row (ADA 2016), so 2 chosen days become 3. Notes for model-flagged At-Risk, PCOS (2023 guideline, citation added) and high risk.
- **Safety:** the cap is merged by the rule engine and can only restrict; unknown intensity is not scheduled under a cap. The rule repository and its Module 3 oracle are unchanged. A 3,000-person test checks every scheduled exercise passes the rules and the cap.
- **App:** "Your training profile" card on the workout tab (targets vs. the planned week, walking suggestion when short); band on the exercise detail. Specialist weeks (Module 14) are measured against the same profile.
- **Module 5:** the safety adaptations now travel with the exercise (`SessionExercise.safetyNotes`) and are shown on mode selection and manual guidance. A test checks no profile removes a camera-supported exercise (squat, chair squat, push-up, knee push-up).
- **Versions:** plans record `rules-2026.10.1+profiles-2026.10.1`, engine `workout-engine-2026.10.2`. No database rule change, nothing to deploy.
- **Review sheet:** `docs/review/module4_review_sheet.csv` (65 rules, profiles, notes and MET mappings, with empty reviewer columns), generated from the code; `test/review_sheet_test.dart` fails when it is stale.
- **Tests:** full suite 787 pass, 13 skipped, 0 fail. New: `test/module4_profiles_test.dart` (19), `test/review_sheet_test.dart` (1).
- **Still open:** phone verification (Android build blocked by memory, see ledger B1); professional review.

### 2026-10-17 — Rules incident resolved, Aamna merged, dataset analysis + Module 4 phase ledger

- **Database:** no data was lost (sessions and feedback still there); the live rules a teammate deployed had dropped the Module 5/4 sections, so writes were refused. The friend's `database.rules.json` was taken as the base, the 4 Baymax sections (`workoutSessions`, `exerciseFeedback`, `workoutReadiness`, `workoutPlan`) were added before `$other`, all 166 of the friend's rule paths are unchanged; deployed after confirmation and verified identical live. Backups: `firebase-rules-backups/`.
- **Merge:** Aamna's `bd8a2a1` (consultation split, specialist plans) merged as `d787933`; a specialist workout plan now respects the Module 4 screening gate. Fixed the `community_test` ListTile assertion in `settings_screen.dart` (transparent `Material`).
- **Dataset analysis** (`docs/MODULE4_KB_IMPLEMENTATION_PLAN.md`): field completeness, distributions, MET intensity bands. Found that `wrist` was never derived for dataset exercises, so the wrist-injury rule could not reach them; importer fixed (58 entries), catalogue rebuilt (MET counts unchanged), test added.
- **Phase ledger:** `docs/MODULE4_PHASE_LEDGER.md` lists done phases with evidence and the next phases K2–K10 (classification profiles keyed by the Module 2 category, MET intensity bands, explanations, review export).
- **Tests:** full suite 767 pass, 13 skipped, 0 fail (run with `TEMP=D:\tmp\flutter`, `--concurrency=2`).
- **Android build still blocked:** the Gradle JVM runs out of memory (crash log: mmap failed; commit charge 24.9 of 27 GB, C: 0.04 GB free so the page file cannot grow). Needs free space on C: or the editors' Java language servers closed during the build.

### 2026-10-17 — Module 4: knowledge-based personalised workout generation (extends the existing plan generator)

Full write-up: `docs/MODULE4_WORKOUT_KNOWLEDGE_BASE.md`. Built on Aamna's Module 3 engine (`PlanGenerator` + `ExerciseSelector`, curated 73-exercise library), which stays in place.

- **Exercise knowledge base:** free-exercise-db (Unlicense) imported at pinned commit `f00c92c` by `ml/exercise_catalog/build_catalog.py` (idempotent, `--check` mode) into `assets/data/exercise_catalog.json`: 876 records → **871 imported** (5 without instructions dropped), 0 invalid image paths, dataset fields unchanged, derived planning fields separate with provenance.
- **MET:** 27 activities copied verbatim from the public 2024 Adult Compendium pages (`compendium_2024_subset.json`); category/equipment/force/mechanic-based mapping rules → **181 exact, 606 approximate (flagged), 84 unmatched (no MET, never scheduled)**. All curated-library METs were also checked against the Compendium: no disagreements. One calorie formula everywhere (MET × kg × active h).
- **Safety rule repository** (`lib/services/workout_rules/`, version `rules-2026.10.1`, all rules pending review): the Module 3 restrictions moved unchanged (a test shows identical results for 3,000 random people against a copy of the old code), plus screening (warning symptoms / heart condition without clearance → no plan; missing age/height/weight → needs info), injury rules and a program-scope rule (no maximal lifting, no expert dataset exercises). Conservative merging; unapproved rules cannot relax anything.
- **Readiness questions** (new screen; `users/{uid}/workoutReadiness`), **plan snapshots** (`users/{uid}/workoutPlan`, versioned, FNV-1a fingerprint), equipment exercises from the catalogue when the user owns that equipment (labelled as dataset instructions, unreviewed).
- **UI:** gate screen when blocked, readiness prompt, photo thumbnails, "Adapted for you" chips, exercise detail with looping photos, kcal, MET match line, rule notes, technique source. Dashboard, chatbot and voice coach no longer present a blocked plan as rest days.
- **Fixed while doing this:** the post-merge commit had restored an older exercise detail screen (lost Aamna's reasons/equipment/"Start exercise" version) — rebuilt from hers; the posture mode screen's notification bell did nothing (now the shared bell); `UserSession._rebuildPlan` dropped "Too Difficult" adjustments.
- **Tests:** 487 pass, 13 skipped, 1 failing (`community_test` settings — fails identically on commit fb98995, not touched here). New: `test/workout_rules_test.dart` (16), `test/module4_test.dart` (26).
- **Not done / blocked:**
  - **Database rules:** the live rules changed since 2026-10-15 — someone deployed a version **without** `workoutSessions`/`exerciseFeedback` and with new `dietReviews`, `specialistPlans`, `planChoice` and changed `appointments`/`slots` rules that this branch does not have. Nothing was deployed; the files must be merged with the newest teammate rules first. Until then Module 5 session saving and Module 4 readiness/plan storage are refused by the live database.
  - **Android build** could not run: drive C: is full (0.04–0.13 GB free) and Gradle keeps its caches there. Tests were run with `TEMP=D:\tmp\flutter`.
  - No professional review of rules, MET mappings or derived fields; readiness clearance is self-reported.

### 2026-10-15 — Modules 5 and 6 verified on a phone (Redmi Note 11, Android 13)

Checked by the module owner on the device, with logs/Firebase checked from the dev PC:
- **Camera detection:** live preview, MediaPipe skeleton aligned with the body, reps counted (e.g. 12 counted, 1 shallow attempt rejected as "too shallow"), "Keep your back straight" shown when leaning too far forward, summary with real score/duration.
- **Frame rate:** ~14 FPS with a person in view indoors in the evening (13.2 FPS measured with nobody in view). Just under the 15 FPS target in dim light; the camera's own frame rate (16–18 FPS in dim light) is the main limit. Re-check in good lighting before reporting NFR-P4 as met.
- **Voice assistant:** speech-to-text → Dialogflow (`repCount` confirmed in the backend log) → spoken reply with the live rep count. When the backend is not running, it falls back to the on-device rules and the card says so.
- **Saving:** workout sessions and a "too difficult" mark (Sit-to-Stand) are stored in Firebase under the user's own node.
- **Running it:** the phone must be on the same Wi-Fi as the PC, and the backend must be running (`cd backend`, then `PORT=3001 node server.js`). The debug app is built with `--dart-define=API_BASE_URL=http://192.168.100.101:3001`; rebuild with the new address if the PC's IP changes.

Remaining (outside these two modules): injury-risk notice waits on the Injury Risk module; iOS code is written but not compiled (needs a Mac).

### 2026-10-14 — Modules 5 and 6: Dialogflow, iOS, saved sessions, "Too Difficult", device tuning aids

Closes most of the open items from the 2026-10-13 entry below (the injury-risk notice stays waiting on that module).

**Dialogflow (report M6 FR-2)**
- Backend: `POST /api/voice/intent` and `GET /api/voice/status` (`backend/routes/voice.js`, `backend/services/dialogflow.js`). Calls the Dialogflow ES `detectIntent` REST API with a service-account key that stays on the server (`DIALOGFLOW_KEY_FILE` in `.env`; `backend/secrets/` is git-ignored). Only the transcript is sent, with a hashed session id instead of the Firebase uid.
- Agent: `node tools/build_dialogflow_agent.js` writes `backend/dialogflow/agent/` and `baymax-coach-agent.zip` (18 intents named exactly like `CoachIntent`, plus `@exercise` from the exercise library and `@topic`). A test checks the agent and the app agree on intent names.
- App: `HybridIntentService` (`lib/services/voice/dialogflow_intent_service.dart`) asks Dialogflow first and falls back to the on-device rules when the server says it is not configured (5-minute back-off), fails or takes over 2.5 s (30-second back-off). Pain/symptom reports are always handled on-device first. The screen shows which engine answered.
- **Agent created (2026-10-14):** Dialogflow API enabled on `baymax-148da`; ES agent `baymax-coach` (trial/standard tier, English, interaction logging off) created and restored from `baymax-coach-agent.zip` via the API. Checked with the live agent: all 26 phrases from the app's intent tests are classified correctly, with `@exercise`/`@topic` values extracted. The generator now writes the zip itself, because Windows PowerShell's `Compress-Archive` stored backslash paths that Dialogflow rejected. Low-confidence Dialogflow answers (< 0.6) that disagree with a rule match defer to the rules.
- **Credentials done (2026-10-14):** service account `baymax-dialogflow@baymax-148da.iam.gserviceaccount.com` with role "Dialogflow API Client" (granted by the project owner; Editors cannot grant roles). Its JSON key is at `backend/secrets/dialogflow-key.json` (git-ignored) and `backend/.env` points to it. Verified: the backend's own Dialogflow call returns the right intents (rep count, technique with `exercise=lunge`, pain, fallback). Not yet verified: a signed-in request from the phone app (needs a login).

**iOS camera detection**: `ios/Runner/PoseLandmarkerPlugin.swift` (same channel contract as Android, BGRA frames rotated upright in memory), registered in `AppDelegate.swift` and added to the Xcode project; new `ios/Podfile` adds `MediaPipeTasksVision` and the `permission_handler` macros. The pose model moved to Flutter assets (`assets/models/pose_landmarker_lite.task`) and is passed to native code by Dart on both platforms, so the Gradle download step was removed. **Not compiled** — this needs a Mac with Xcode (`cd ios && pod install`, then `flutter run`).

**Saved sessions**: every finished session is written to `users/{uid}/workoutSessions/{pushId}` (summary numbers and feedback text only — never frames or landmarks) by `lib/services/workout_session/workout_log_service.dart`. The summary screen shows "Saved…" or the error with a retry. `database.rules.json` gained validated `workoutSessions` and `exerciseFeedback` nodes. **The new rules must be deployed** (`firebase deploy --only database`) before saving works on a device.

**"Too Difficult" (FR17.4)**: stored at `users/{uid}/exerciseFeedback/{exerciseId}` and loaded by `UserSession`. `PlanGenerator.generate(…, tooDifficult:)` swaps each flagged exercise for an unflagged one of the same group that is no harder; if none exists it keeps it with one set fewer and ~30% fewer reps/seconds, and adds a note explaining the change. Flags older than 28 days are ignored.

**Threshold tuning aid**: debug builds log angles, phase, inference time, FPS and every counted/partial rep (`adb logcat -s flutter | grep "\[pose\]"`). Only numbers are logged.

**Frame-rate work (NFR-P4, ≥ 15 FPS)** — measured on the Redmi Note 11 with `integration_test/pose_benchmark_test.dart` (`flutter test integration_test/pose_benchmark_test.dart -d <device>`), indoors in the evening, **nobody in view** (so MediaPipe runs its slower person-search step on every frame):

| Change | Camera delivers | Pose analysed |
|---|---|---|
| Before (CPU model, full-size frames, 1 frame in flight) | ~11 FPS | 5–7 FPS (user-reported 8) |
| + model on GPU, frames halved during conversion (3 ms), camera asked for 30 FPS | 16–18 FPS | 7.8 FPS |
| + two frames in flight (`CameraPoseStream.maxFramesInFlight`) | 16 FPS | **13.2 FPS** |

Model time on the GPU: ~39 ms with synthetic frames, ~52 ms live. **15 FPS is not yet demonstrated**: remaining limits are the camera itself in dim light (16–18 FPS) and the person-search step, which MediaPipe skips while it is tracking a person. Next measurement needed: the same benchmark/app with a person in view in normal light. A 3-frames-in-flight variant could not be tested because the phone blocked the USB install (Xiaomi "Install via USB" confirmation).

**Verification**: 194 automated tests pass (new: Dialogflow mapping/back-off/timeout/safety, agent ↔ app intent names, save/retry, stored fields ⊆ database rules, plan swaps and lighter doses). Android debug APK built and installed on a Redmi Note 11 (Android 13, arm64); the app starts. Camera, pose inference, FPS, voice and threshold tuning on that phone are still pending (see below).

### 2026-10-13 — Real-Time Posture Detection and AI Micro-Coaching Voice Assistant (report Modules 5 and 6)

Module numbers here follow the FYP report (5 = posture, 6 = voice). The five screens existed only as mock-ups (timer-driven reps, hardcoded 85% score, a permanent "Listening…" animation); they now run on real data.

**Navigation (same as the React prototype)**
Dashboard "Posture Check" tile or Exercise Detail "Start Exercise" → Select Mode → Camera Detection *or* Manual Guidance → Session Summary → "Back to Workout Plan" / "View Analytics". The voice assistant opens from the chatbot's mic icon, and from the camera screen's ⋮ menu and the manual screen's mic icon so it can be used mid-session.

**Posture detection** (`lib/services/posture/`)
- **MediaPipe Pose Landmarker (33 landmarks)** runs natively on Android: `android/.../PoseLandmarkerChannel.kt` ↔ `pose_estimator.dart` over the `baymax/pose_landmarker` channel. Camera frames (`camera` plugin, NV21) are converted and analysed in memory on a background thread; nothing is saved or uploaded. One frame is in flight at a time, later frames are dropped.
- `pose_math.dart` — joint angle θ = arccos(BA·BC / |BA||BC|), cosine clamped to [-1, 1], null for zero-length vectors or invalid coordinates. Angles use MediaPipe's 3-D world landmarks.
- `exercise_form_rules.dart` — per-exercise, editable thresholds. Supported with the camera: **squat, sit-to-stand, push-up, knee push-up**. All other exercises offer Manual Guidance only. *The thresholds are the team's starting values from common coaching cues; they are not validated on test subjects or reviewed by a physiotherapist.*
- `rep_counter.dart` — state machine top → descending → bottom → ascending → top; a rep counts once, on the return to the top, only if valid depth was reached. Guards: hysteresis, smoothing, single-frame outlier rejection, minimum rep duration, tracking-loss reset.
- `posture_engine.dart` — form checks per frame, live corrective feedback, scoring:
  - **Posture score** = 100 × reps with acceptable form ÷ attempted reps (counted + too-shallow attempts) — report FR18.1. Not shown until one attempt has finished.
  - **Accuracy** = 100 × passed check-frames ÷ assessed check-frames. Frames without confident landmarks are excluded from both.
- `pose_stream.dart` — camera lifecycle, back-pressure, measured FPS (shown live and on the summary).

**Voice assistant** (`lib/services/voice/`)
- Pipeline: `speech_to_text` → `IntentService` → `CoachResponder` → `flutter_tts`; states idle / listening / processing / speaking / error / unavailable drive the UI and the waveform (mic level while listening).
- **Dialogflow is not connected** — there are no credentials and no backend route. Intents come from `RuleBasedIntentService` (on-device keyword rules), and the screen says so. To add Dialogflow, implement `IntentService` against a backend proxy that holds the service-account key, and pass it to `VoiceAssistantController(intents: …)`.
- Answers use live session state: rep count, latest form correction, score, elapsed time, current exercise and technique steps, today's plan from `UserSession`. With no data it says so. Pause/resume work by voice; ending a session asks for confirmation. Pain or symptoms → "stop and seek help", no diagnosis.
- `posture_cue_announcer.dart` speaks posture corrections during a camera session, rate-limited (≥5 s apart, same cue not within 15 s, silent while the assistant is open).

**Shared session state** — `lib/services/workout_session/workout_session_controller.dart` (`ChangeNotifier` singleton, like `UserSession`). The posture engine and manual screen write to it; the voice assistant and screens read it. Summaries are kept in memory only.

**Integration points for the Workout Plan module**
1. Start a session: `Navigator.push(… PostureModeSelection(request: WorkoutSessionRequest.fromPlanned(planned, upNext: restOfTheDay)))`. `exercise_detail.dart` already does this for the tapped exercise (without `upNext`). Passing `upNext` enables "Next Exercise →" and the "what's next?" voice answer.
2. Read results: `WorkoutSessionController.instance.lastSummary` / `.history` (`SessionSummary`: reps, duration, score, feedback, `skipped`, `tooDifficult`). "Too Difficult" is recorded but nothing consumes it yet (report FR17.4).
3. `lib/screens/posture_detection/exercise_picker.dart` is a **temporary** test screen behind the dashboard tile; its sets/reps are library defaults, not a prescription. Delete it once the plan passes exercises in.

**Not done / deviations from the mock-up**
- Sessions are not saved to a backend: no workout-logging endpoint exists and the Realtime Database rules reject unknown fields.
- The summary's "Injury risk remains Low" banner is replaced by a note that the Injury Risk module is not connected.
- The camera-consent switch starts **off** (the mock-up had it on) so consent is explicit (FR15.3).
- **iOS:** no native pose implementation yet (the screen reports "available on Android only"); usage strings were added to `Info.plist`. `permission_handler` also needs its Podfile macros when the iOS project is first built.

**Config changes**: `pubspec.yaml` (+ `camera`, `permission_handler`, `speech_to_text`, `flutter_tts`); Android manifest (+ `CAMERA`, `RECORD_AUDIO`, speech/TTS `<queries>`); `android/app/build.gradle.kts` (+ `com.google.mediapipe:tasks-vision`, and a task that downloads `pose_landmarker_lite.task` into `android/app/src/main/assets/` on first build — git-ignored).

**Verification**
- `flutter test`: **179 pass** (79 existing + 100 new in `test/posture_test.dart`, `test/voice_test.dart`, `test/posture_screens_test.dart`). The new tests drive the real engine with synthetic landmark sequences and the screens with fake camera/microphone/TTS.
- `flutter analyze`: no errors or warnings (the new files add no issues).
- `flutter build apk --debug` succeeds on Windows; the APK contains `libmediapipe_tasks_vision_jni.so`, `assets/pose_landmarker_lite.task` and the `CAMERA` / `RECORD_AUDIO` permissions.
- **Nothing has been run on a phone.** Live camera preview, real MediaPipe inference, skeleton alignment (incl. front-camera mirroring), FPS, speech recognition and TTS all still need a physical Android device. The 15 FPS target (NFR-P4) is unmeasured; the camera screen shows the live rate and the summary shows the session average, so it can be read off a device.
- MediaPipe 0.10.26 ships its native library for **arm64-v8a only**: it runs on 64-bit ARM phones, not on x86 emulators or 32-bit devices (those get a "could not start the pose model" message).
- `permission_handler` is pinned to `^12.0.1`: version 13 requires Android SDK Platform 37, which is not installed on the dev machines.

### 2026-10-15 — Food search is now a suggestion dropdown
Typing in "Search foods" shows a scrollable dropdown under the box (compact rows: name, "Also called <other name>" when the match came from another name such as
"chawal", serving, kcal, source, and a red allergy warning when the food contains something on the user's allergy list). Tapping a row adds it to the meal. Also fixed:
the portion row (- / + and serving/g/ml) overflowed on narrow phones; the unit selector is now on its own line. 4 widget tests added (`merged_scope_screens_test.dart`).
Not tried on a phone.

### 2026-10-15 — Searchable food list: team data (amna.zip) + Indian Nutrient Databank + USDA, loaded into Firestore
User asked to unzip the provided food data, use USDA data too, populate Firestore and make the app search that data.
- **Built** with `ml/food_catalog/build_catalog.py` (reads the extracted CSVs; report lists everything dropped) -> `assets/data/foods_bulk.json`, **2,760 foods**:
  787 from the team's Calorica lists (+ beverages/fruits/vegetables.csv; Pakistani/Indian names and spellings become search aliases; each row keeps the origin it
  names: USDA / INDB / CURATED / brand-official), 930 from the Indian Nutrient Databank (`ind.csv`, recipe-based, per serving), 1,043 from USDA SR Legacy
  (`ml/usda_foods/foods_usda_sr_legacy.json`). **All 1,043 USDA foods were checked against the zip's own `food.csv`/`food_nutrient.csv`**: 1,042 match exactly, one
  differs by 0.27 g fat (rounding). 183 rows were left out as duplicates of a curated/earlier food. **30 INDB rows (soups/sauces) were dropped because their listed energy
  contradicts their own protein/carb/fat** (e.g. Lentil soup 31 kcal with 9.7 g protein + 11.7 g fat per 100 g). 12 other rows kept although energy differs >50% from macros
  (alcohol, bran, USDA energy factors). The USDA `branded`, `FNDDS` and `foundation` tables in the zip (about 2 million rows, mostly brands) were **not** loaded.
- **Firestore:** `foods` now holds **2,857 docs** (97 curated + 2,760), `meta/foods.version` 1792054236. Seeded with `Baymax-main/tools/seed_firestore.js "foods.json,foods_bulk.json"`
  (new: several files, optional service account via `GOOGLE_APPLICATION_CREDENTIALS`). **The provided service-account key authenticated but has no Firestore permission
  (403)**, so the seed ran with the owner's `firebase login` session instead. The key file stays in Downloads, was not copied into the project and must never be committed.
- **App:** food search uses Firestore first (cache-first, refreshes only when `meta/foods.version` changes); the bundled `foods_bulk.json` is only the offline / not-yet-seeded fallback.
  Search keys are computed once (fast with 2,800 foods). Foods show their source (USDA / INDB / team list); logged entries store `usda:`, `indb:` or `calorica:` refs.
  Nothing in these lists has allergen data: **allergens are guessed from the name (including roti/naan/ghee/paneer etc.), over-warn, and are marked "estimated"**.
  These foods have no meal slots so they never enter generated plans. Sources screen updated (INDB paper cited: Vijayakumar et al., Curr Dev Nutr 2024, doi 10.1016/j.cdnut.2024.103790).
- **Not verified:** the usage licence of the team list and of the INDB table (the INDB paper calls it open but names no licence) - check before the GitHub repo (public) keeps
  `foods_bulk.json`. Calorica rows marked CURATED cite no outside source. Not tried on a phone.
- **Cloud state:** RTDB rules (water, moods, inbox, foodDays, settings) **deployed** after retrying through a process-local DNS fallback; anonymous read/write of `users/x/...` -> 401.
  **Live Firestore rules differ from `firestore.rules`**: anonymous reads of `foods`, `exercises`, `meta` return 200 (the repo rules require sign-in). Not changed without asking.
  Quota note: every device downloads ~2,857 docs when the catalogue version changes (free plan: 50,000 reads/day).

### 2026-10-15 — Audit against the merged scope (Baymax_Merged_Report_Chapters_1-5) and the gaps closed
Scope numbering used here: 1 Auth & Onboarding, 2 AI Health Classification, 3 Home Dashboard, 8 Diet & Calorie Tracking, 9 Nutrition Plan,
12 Community Ranking & Gamification, 16 Secure Data Management & Smart Alerts. Decisions taken with the user: no new packages, deploy the
RTDB rules, download USDA data, and where the scope contradicts itself follow safety and the module's own feature list.

**Added (no new packages; 247 tests pass, `dart analyze lib test` has no errors or warnings, `flutter build apk --debug` builds):**
- **Module 1:** inline validation with the scope's exact rules (name, email, password 8+ with uppercase/number/symbol, confirm, age >= 13, height
  50-300 cm, weight 20-500 kg, target weight), Create Account disabled until valid + terms ticked, "Sign up with Google", login lock after 5
  failures for 15 minutes (`LoginGuard`, in memory), tagline, unit conversion on the cm/ft and kg/lbs toggles, honest privacy notice on step 2.
- **Module 2:** "Recommended actions" cards and "Your first step" on the result screen, every figure from the user's own plan.
- **Module 3:** time-of-day greeting line, calories burned / active minutes / calories eaten cards, mood check-in saved per day with a suggestion,
  notification bell with unread count, floating chat button on Home. **Steps shows "-" (no step sensor; needs a pedometer package).**
- **Module 8:** water tracker, collapsible meals with subtotals and a "+" per meal, serving/g/ml units with +/- steps, recent foods, delete with undo,
  Daily summary screen (consumed / burned / net, calories by meal vs target, macro donut, 7-day chart, goal-worded verdict that never praises a very
  low intake), and a **1,000+ food search**: the 97 curated foods plus 1,074 USDA FoodData Central SR Legacy foods (CC0, `assets/data/foods_usda.json`,
  generator `ml/usda_foods/build_usda_foods.py`, see its README). USDA has no allergen data: bulk-food allergens are **guessed from the name**
  (over-warning), flagged `role: usda`, the app says "estimated", and they never enter meal plans (`meals: []`). Listed in Sources.
- **Module 9:** fixed "For your health" notes plus rotating "Pro tips" (3 a day, 28+ in the pool, none repeats within 7 days).
- **Module 12:** podium for the top 3, level filter chips, week number and "Resets in 3d 5h" countdown, own row pinned, My badges screen (XP level, active
  streak, earned badges newest first with the week, locked badges show how to unlock), 7-day and 30-day streak badges (catalogue is now 10), lifetime XP
  (50 per workout day, 10 per meal-logged day, 100 per badge; level L starts at 100 x L x (L-1)).
- **Module 16:** notification inbox (stored in RTDB, tabs All/Workout/Diet/Alerts, mark all read, tap opens the screen), reminders that came due while the
  app was closed are created when it opens, meal-log reminder, badge and allergen notifications, master "Allow notifications" switch.
- RTDB rules extended (`water`, `moods`, `foodDays`, `inbox`, new settings fields).

**Not done, and why:** real step count (needs a pedometer package; not approved) - custom camera viewfinder/flash (camera package) - emergency contacts in secure
storage (flutter_secure_storage) - app-level AES-256 (the app states only what is true: encrypted connection, Google encrypts stored data at rest by
default) - FCM push, so reminders are local notifications plus the inbox - injury-risk alerts - "50 Squats" / "Perfect Form" badges (no rep or posture data) -
email on login lock (the lock is app-side; Firebase also rate-limits) - units preference in Profile - Weekly Report notification (no weekly report screen).
Modules 4, 10, 13, 17 were not audited line by line.

**Scope conflicts:** Module 12 FR-9 (show unlock requirements) vs M33.4 (hide criteria) - followed FR-9. M5 FR5.4 "AES-256 encrypted" - replaced by the true statement above.

**Not verified:** nothing was run on a real phone or against live sign-in. **The new RTDB rules are NOT deployed**: `firebase deploy` failed because this Mac
cannot resolve `firebasedatabase.googleapis.com` (local DNS; the same problem blocked fdc.nal.usda.gov earlier). Run
`firebase deploy --only database --project baymax-148da` on another network, then confirm anonymous reads and writes of `users/x` still return 401. Until then the
water, mood, inbox and meal-day writes are refused by the old rules and those features fail quietly. The Google encryption statement rests on Google's general
encryption-at-rest documentation; a Realtime-Database-specific page was not found.

### 2026-10-14 — Dialogflow REMOVED; chatbot now answers from the user's own history

- **Decision (user):** no Dialogflow; the chatbot should answer from the user's personal data. Everything Dialogflow-related was deleted: `Baymax-main/dialogflow/`, `services/dialogflow.js`, `services/limiter.js`, `routes/chat.js`, the backend tests, `app/lib/services/dialogflow_service.dart`, its tests, the chat-screen "Dialogflow / On-device" captions, and the Dialogflow entries in the Sources screen and privacy summary. The two earlier log entries below about Dialogflow are kept only as history; **none of that code exists any more**. Nothing was ever created in a cloud account.
- **Module 8 (allergy scanner) is NOT removed.** I removed it by mistake while reading the request, then restored it from a backup made first (screens, `allergen_matcher.dart`, `ocr_service.dart`, `routes/scan.js`, every entry point and test). The user's decision is only that it is not being worked on now. State: unchanged from before (built and tested; OCR still needs a Google Vision key that is not set).
- **New: `services/chat_history.dart`** reads the user's own account (last 7 days of meals, 28 days of workouts / logging / streaks / badges / weekly score, 28 days of weigh-ins, how the calorie target was worked out). Each part is loaded separately; a part that cannot be read is `null`, and the bot then says "I can't read your ... right now" instead of claiming the user did nothing.
- **New answers** (`chatbot_engine.dart`): weekly summary with the weakest area and a nudge ("how am I doing"), streaks / badges / level and the next badge, last workout and workouts in 4 weeks, what I ate today or yesterday by meal, macros left against the plan, 7-day eating average and on-target days, weight progress (latest, change, trend, distance to target, wrong-direction warning for the user's goal), why the calorie target was adjusted.
- **Existing answers personalised:** calories left and protein come from the food log; meal suggestions mention what is already logged and the calories left; "can I eat X" shows what it does to today's calories (on top of the allergy check); today's workout says if it is already done and how the week is going; the greeting adds "Today so far"; the calorie-target answer uses the app's real target. Suggestion chips follow the user's situation. Intent ties now go to the longest matching phrase.
- **Safety unchanged:** symptoms, emergencies, doctor requests and risky topics are answered first, whatever the history says (tested). Still rule-based and on the phone: no data leaves the device for the chatbot.
- **Tests:** 207 pass (new `test/chatbot_history_test.dart`, 20 tests: every new answer against hand-built histories, the "can't read" behaviour, personalised versions of old answers, routing, safety, suggestions, and the chat screen loading the logs). `lib/dev/preview_main.dart` `chatbot` uses demo history.
- **Not verified:** on a phone with a real account and real logs (the tests use hand-built histories; the emulator preview was not re-run for this change). The answers are only as good as what the user has logged.

### 2026-10-14 — Dialogflow kept free-only (user rule: nothing paid)

- **Checked** Google's Dialogflow ES documentation: the **Trial Edition** has "No charge" for text with a 180 requests/minute quota; **Essentials** is $0.002 per text request. The plan is text only on the Trial Edition. **Not confirmed in the docs:** whether a billing account/card is demanded when enabling the API or creating the agent, and whether the Trial has an expiry. Rule in `dialogflow/README.md`: if the console asks for a card, do not set Dialogflow up (the chatbot works without it).
- **Added guards** (`Baymax-main/services/limiter.js`, used by `routes/chat.js`): 20 requests/user/minute, 120/minute server-wide (under the 180 quota), 1,500/day (`DIALOGFLOW_DAILY_LIMIT`). Over the limit the route answers 429 and the app answers on the phone. `npm test`: 11 pass.
- Other paid-service risk to decide separately: the Google Vision OCR key for Module 8 (not changed here; its free allowance and billing requirement have not been checked).

### 2026-10-14 — Module 12: chatbot intent detection through Dialogflow ES (code done; agent not created yet)

- **Design (hybrid, health-safety first):** (1) symptoms, emergencies, doctor requests and risky topics are answered **on the phone first**, with no network call; (2) otherwise the sentence goes `app -> Baymax backend (/api/chat/detect) -> Dialogflow ES` and comes back as an intent name plus parameters (food, exercise, meal slot); (3) the answer text is still written **on the phone** from the user's profile and plan, so no health data is sent to Google; (4) if Dialogflow is not configured, offline, slower than 5 s, below 0.55 confidence, a fallback, or an intent the app does not know, the existing keyword matcher answers. Each reply is captioned "Dialogflow" or "On-device".
- **Backend** (`Baymax-main`): `services/dialogflow.js` (service-account JWT signed with Node's `crypto`, token cached, `detectIntent` over REST; **no new npm package**), `routes/chat.js` (Firebase-auth required, only the sentence is forwarded, session id is a hash of the uid, 503 when not configured), `.gitignore` now excludes service-account keys, `npm test` runs 7 tests (token claims verified with a generated key, request shape, failures).
- **Agent** (`Baymax-main/dialogflow`): `build_agent.py` generates `baymax-agent.zip` (30 intents, 200 training phrases, `@food` 97 and `@exercise` 71 entities taken from the app's own catalogues, `@meal_type`) and `INTENTS.md`; `README.md` has the setup steps. 16 FAQ intents map to the app's FAQ answers by id.
- **App:** `services/dialogflow_service.dart` (`IntentDetector`, backs off 10 min after "not configured" and 60 s after any failure so the chat never waits on a dead service), `ChatbotEngine.respondSmart` / `replyForIntent`, chat screen with typing dots and the source caption; Sources screen and privacy summary updated.
- **Tests:** 204 pass (new `test/dialogflow_test.dart`: Dialogflow path, every fallback, safety order, a detector that must not be called for symptoms, parameters, the detector's back-off, the chat caption, and a check that every intent in the agent export has an on-device answer).
- **NOT done / not verified:** no Dialogflow agent, service account or key exists (those are cloud resources and credentials, which the user creates: see `dialogflow/README.md`). The ZIP follows the ES export format but has **not been imported**, and **no live Dialogflow request has ever been made**. Until the user sets it up the app behaves exactly as before (the caption says "On-device").

### 2026-10-14 — Scope audit: what is built and working (no code changed)

- **Scope has 15 modules / 98 feature IDs.** Status by feature ID: **45 working** (covered by automated tests and/or seen working in the emulator preview), **15 partial** (built but needs a key, a device test, or uses a different method than the scope names), **38 not built** (Modules 5, 6, 9, 13 entirely; most of 4; parts of 10, 14, 15).
- **Checked today:** 187 tests pass (0 fail); `flutter build apk --debug` OK; the Node backend starts and `/api/scan/ocr` rejects a missing token; the Realtime Database refuses anonymous reads (401) and the food catalogue refuses anonymous writes (403). `GOOGLE_VISION_API_KEY` and `USDA_API_KEY` are **not set** in `Baymax-main/.env`. A note: the Firestore food catalogue is readable without signing in over REST (200); it holds no personal data, but the earlier note that it returned 403 no longer holds.
- **Not checked (needs the user on a real phone with a real login):** register / login / Google sign-in, saving and reloading a profile, the live leaderboard, scheduled notifications firing, camera and gallery pickers, OCR on a real label, the food model running on a phone.

### 2026-10-14 — UI revamp 2: "aurora glass" design system, guided session, honest onboarding

- **"Taste" skill:** none is enabled on the account. The closest directory plugin (VectorLab UI/UX Skills: typography, colour, spacing, surfaces, motion) was offered again as an install card, **not installed**; the work below was done without it.
- **Look (unisex):** replaced the pink theme with a cool mist background (indigo / violet / teal light), frosted white glass cards with layered soft shadows, deep-indigo actions (`AppTheme`: `primary` 4338CA, `teal`, `heroGradient`, spacing scale and radii). Type is Plus Jakarta Sans (google_fonts; system font offline) with a full hierarchy in `textTheme`. Status colours were darkened so they stay >= 4.5:1 on their own tints (success 0A6640, warning 874C00, error 9E1E17, teal 086B60); `test/ui_test.dart` checks it.
- **Emoji removed everywhere** (screens, chatbot replies, notification titles, badges). Catalogue data still carries an emoji `icon` field, but it is never drawn: `theme/app_icons.dart` maps foods, exercise groups, meals and badges to Material icons. `AppBadge.emoji` was removed.
- **Components** (`widgets/glass.dart`, `progress_ring.dart`, `forms.dart`, `brand.dart`): `Pressable` (press-in scale, ripple, light haptic; every card/tile/button now gives feedback), `GlassCard`, `IconWell`, `InfoChip`, `SectionHeader`, `Reveal` (staggered fade/slide, off when the system asks for reduced motion), `ProgressRing`, `MessageState`, a nav bar whose indicator slides between tabs, `StepHeader` / `PillChoice` / `SelectChip` for the profiling flow, `BrandMark`.
- **Every screen restyled:** splash + onboarding, login, sign-up, profiling steps 1-3 ("None" is now exclusive in medical conditions and allergies), BMI result, health summary, home, diet, workout, exercise detail, analytics, profile, community, calorie target, nutrition plan, settings, sources, specialists, body transformation, chatbot, voice preview, allergy scanner and result, food scan and log, drawer, posture screens.
- **Responsive:** content is held to a 680 px column and centred on tablets; text scaling is capped at 1.3; grids use fixed row heights that grow with the text size (the old aspect-ratio grids overflowed at large text); bottom spacing comes from `MediaQuery.padding` so tab screens clear the floating bar and pushed screens do not leave a gap.
- **Navigation / buttons that did nothing, found and fixed:** posture "Continue" with Manual guidance selected did nothing; camera "Stop Session" did nothing; the dashboard quick tiles and cards had no touch feedback. The home chat button was removed (it covered a tile; the chatbot is a tile, in the menu and on Specialists). Terms of Service / Privacy Policy on sign-up are now tappable and open a short plain-language summary (**written by me, not a legal document; the team should replace it**).
- **Guided session (new, replaces fake posture screens):** `ManualGuidance` now walks the user's real exercises (from the opened exercise onward, or today's workout): technique cues from the plan, a countdown for timed exercises or a set counter for rep-based ones, Done / Skip / Too difficult, leave-confirmation on back. The summary shows only what the app observed (exercises done/skipped, sets ticked, time). **Removed invented content:** the old summary showed a made-up 85% posture score, "12 reps" and "Injury risk remains Low". Camera detection is kept as a screen but is labelled **Preview, simulated** (no camera or pose model is connected).
- **Honesty fixes in copy:** onboarding no longer claims real-time posture correction by computer vision; the mood selector on Home says it is not saved yet (Module 6 is a teammate's); the long-press "test" screen on the logo only opens in debug builds.
- **Verified how:** a temporary Android emulator (created and deleted again) ran `lib/dev/preview_main.dart`; about 30 screens were checked by screenshot, and taps on the tab bar, drawer, drawer items, mode selection and the guided session were exercised. Issues found that way and fixed: title not aligned with content, "Log food" button hidden behind the nav bar, workout CTA overlapping the bar, an exercise hero that did not fill the width, chips and rich text in the wrong font, a translucent drawer showing text behind it. **Not verified:** a physical phone, iOS, TalkBack, dark mode (light theme only), landscape, large-font settings on a device (only via tests), real signed-in data (the preview uses demo data and shows "not signed in" on screens that read the database).
- **Tests:** 187 pass (new `test/guidance_test.dart`: Continue opens the session, a full session reaches an honest summary, exercise detail hands the session on, legal links, press feedback; existing tests updated for new wording). `flutter build apk --debug` succeeds.

### 2026-10-13 — UI revamp: baby-pink glass theme, working navigation, accessible colours

- **"Taste" skill:** none was enabled on the account; the closest directory plugin (VectorLab UI/UX Skills) was offered as an install card, not installed. The design below was done without it.
- **Look:** soft pink gradient behind every screen with glowing orbs (`widgets/glass.dart` `GlassBackground`, applied once in `main.dart`; all Scaffolds are transparent), frosted `GlassCard`s (translucent white, light rim, pink glow; ~30 existing cards converted via `AppTheme.glass`), glowing raspberry buttons, a floating frosted bottom bar (`GlassNavBar`, blur used only here), Material icons in place of pale emoji on stat/tile cards, Nunito font via google_fonts (loads when online; falls back to the system font offline), pink status-bar handling.
- **Visibility (checked by test):** palette is deep-plum text, raspberry accent, baby-pink surfaces. `test/ui_test.dart` computes WCAG contrast: every text colour >= 4.5:1 on the lightest and darkest gradient stops and on the glass cards, white on every button colour >= 4.5:1. Found and fixed real invisible-text bugs: white labels on pale cards in profiling Step 3, white "Continue with Google" text, white chip text on the camera screen, grey/muddy tinted chips (replaced by `AppTheme.tint`), weak orange/red macro colours, a switch whose thumb vanished (`activeColor` clash), a dark voice-assistant screen.
- **Navigation fixed:** new menu drawer (`widgets/app_drawer.dart`) reaching every screen (5 tabs, calorie target, nutrition plan, allergy scanner, posture, body transformation, community, chatbot, voice assistant, specialists, settings, sources, log out); the dashboard menu icon and the three notification bells (dashboard, workout, posture) now open it / the reminders settings; "Body Transform" and "Find Specialist" tiles open real screens; the Analytics tab is a real screen (calories vs target with 3-day moving average, weekly fitness score, weight trend; built from data the app already records; injury-risk trend needs Module 9 and says so); Skip / Too Difficult (manual guidance) and the camera menu work; voice-assistant chips work and the screen says it is a preview with an example answer built from the user's real plan. A test fails if any `onPressed: () {}` / `onTap: () {}` is added.
- **New screens:** Analytics (partial Module 15), Body transformation (straight-line extrapolation of the user's own weigh-ins via `services/weight_projection.dart`, clearly NOT the scope's forecasting model), Find a specialist (says plainly that consultations are a later release; links to the chatbot and health summary).
- **Layout fixes:** action buttons (Log Food, Start Today's Workout) lifted above the floating bar; chat shortcut only on Home so it never covers content; extra bottom padding; replaced a hot-linked Wikipedia image in the camera mock (it failed with an HTTP error and contradicted "processed locally") with a local icon.
- **Bug found by looking at the screen, not by tests:** the weight "Save" button sat in a Row but the theme gives buttons infinite width, so the whole Calorie target screen failed to lay out. My earlier widget tests used the default Flutter theme and missed it; screen tests now use `AppTheme.lightTheme`.
- **Verified how:** a development-only entry point (`lib/dev/preview_main.dart`, a launcher grid with demo data; not part of the app) was run on a temporary headless Android emulator (created and deleted again) and ~30 screens were checked by screenshot. **Not verified:** real signed-in flows, a physical phone, iOS, TalkBack/screen-reader use, large-font settings, dark mode (the theme is light only).
- **Tests:** 180 pass (new: 17 in `test/ui_test.dart`).

### 2026-10-16 — Folder layout: app, specialist portal, admin panel and API each in their own folder

- Before: the API lived inside `baymax-portal/server`, so the admin panel depended on a sibling's subfolder, and the GitHub snapshot repo held a `portal/` copy. Now: `~/Downloads/baymax-portal` = specialist portal only (:3000), `~/Downloads/baymax-admin` = admin panel only (:3001), `~/Downloads/baymax-api` = the Express API both call (:4000) with its `e2e/` and `emulator/`. The app stays in `untitled folder/app`. No folder contains another; paths in scripts, tests and READMEs were updated (`create-admin.js` writes to `../baymax-admin/.env.admin`).
- Re-verified after the move: API 76 unit tests, emulator e2e 11 + 10 + 3, both web apps typecheck and build, all three servers restarted and answering.
- NOT changed: the GitHub repo (`Baymax-implementation`, branch `Amna's-work`) still contains an older `portal/` copy from commit b8d7768. Remove it (and optionally give the web projects their own repos) on the next push, with the user's OK.

### 2026-10-16 — Phase 1: administrator login saved to a private env file

- `portal/server/scripts/create-admin.js --email <you>`: creates the admin account with a generated 20-character password (random, mixed classes, no look-alike characters) and sets the `admin` role. The login is written to `baymax-admin/.env.admin` (mode 600, git-ignored); the password is never printed or logged. An existing account keeps its password unless `--reset-password`; a doctor/nutritionist/trainer is never converted. It must be run by the user (it creates a real account in the real project), so no credentials exist yet and none were seen by Claude.
- Tests: 5 unit (`adminAccount.test.js`, server total 76) and 3 on the emulator (`e2e/admin-account.e2e.mjs`): the saved login signs in and the admin API accepts it, the file is private, a re-run changes nothing, a reset replaces the password. Found on the way: Node itself swallows a script flag called `--env-file`, so the option is `--out`.
- Phase 2 (specialists view and edit the member's plan) was largely built earlier the same day (see the entry below): not started again until asked.

### 2026-10-16 — Remaining Module 14: patient records, plan editing, food-log review, account deletion, separate admin panel, end-to-end verification

- **Specialists (portal):** My patients + patient record; diet plan (doctor, nutritionist) and workout plan (doctor, trainer) approve-or-change with validation (macros must match the calorie target within 15%, exercises only from the library, 30-day edit window after an accepted appointment); nutritionist approve/flag per day of the food log (reason required to flag); Prescriptions list; close own account (re-enter password + DELETE, cancels future bookings, deletes the sign-in unless the account is also an app member); menu badge + desktop alert for new requests.
- **App:** `models/specialist_plan.dart`, `services/specialist_plan_{apply,service}.dart`, `UserSession` keeps Baymax's plan (`basePlan`) and the one shown (`plan`); a specialist's calorie target/macros/avoid/tips and weekly schedule are layered over it; "Adjusted/Reviewed by ..." banner on the Nutrition and Workout screens with "Use Baymax's plan instead" (member's choice at `users/{uid}/planChoice`); the nutritionist's verdict shows on the Daily summary. Tests: 18 new (364 total pass).
- **Admin panel (separate project `~/Downloads/baymax-admin`, port 3001):** overview, registrations (approve/reject), specialists (add, delete). Admin pages were removed from the specialist portal. API: `/api/admin/*`.
- **Verification on the Firebase emulators** (`portal/e2e`, downloaded the Database emulator with the user's OK): real rules + real token checks + the portal API + a browser walkthrough of registration, rejection and resubmission, approval, accept, patient dashboard, plan editing, notes/prescription, account closing, admin add/delete. Server 71 tests, rules e2e 11, flow e2e 10, app 364.
- **Bugs this found (all fixed):** (1) the deployed rules refused a valid *payment* (a parent `.validate` was applied on every child write, so booking failed at the pay step, and a fee change would have locked members out); fixed in `database.rules.json` and deployed 2026-10-16 with the user's approval (anonymous read/write of the new nodes return 401; the same rules pass the 11 emulator tests); (2) helmet's `Cross-Origin-Resource-Policy: same-origin` made browsers discard every API response; (3) `make-admin.js` / `create-specialist.js` never exited; (4) registration wrote `undefined` to the database; (5) the test database now rejects `undefined` like the real one.
- **Incident:** a first browser test ran against the REAL Firebase project and created an empty real account `doctor1@example.com` (no data). It was verified empty and deleted; the project is back to its 10 original accounts. Cause: the test settings were not exported (zsh does not split `$VAR`); `e2e/start-web.sh` exports them properly.
- **Still not built:** push notifications to specialists (FCM), patient reviews/ratings, client messages, risk-alert/posture/emotion panels (need AI-engine data), refunds, JazzCash (payment is a test gateway). Nothing has been run on a phone.

### 2026-10-16 — Specialist accepts the request, then the video room is made; specialist registration; patient dashboard in the portal

- **Request flow:** after payment (or pay at clinic) a booking is now a **request** (`requested`), not a confirmed appointment. The specialist accepts or declines in the portal. **Accepting makes the video room on the server** (unguessable Jitsi link, `MEETING_BASE_URL` in `portal/server/.env`), sets `confirmed`, keeps the slot and notifies the member. Declining frees the slot, stores an optional reason and notifies the member. A request unanswered at its start time shows as Expired. The phone no longer creates a link (removed `ConsultationRules.meetingLink/newRoomName` and the `MEETING_BASE_URL` dart-define) and the rules forbid a client from writing `meetingLink`, `declineReason` or `respondedAt`.
- **App:** statuses `requested` ("Awaiting acceptance") and `declined`; My appointments lists requests with the upcoming ones and says what happens next, with Cancel request; no video link or Join until accepted; success screen says "Request sent"; Find a specialist shows a Verified badge for approved specialists (`specialists/{uid}/verified`).
- **Portal (`portal/`):** New requests panel with Accept/Decline (dashboard and appointment page), registration at `/register` + applicant screen (pending / rejected-with-reason / resubmit), administrator approval of registrations (licence number visible to admins only, approval creates the role and a `verified` public profile), and the appointment page is now a patient dashboard (tiles, calorie and workout bar charts) from the data the patient consented to, opened only after accepting. Server tests 53, app tests 346.
- **Rules:** updated in `database.rules.json` (new statuses; submitting payment moves `pending_payment` to `requested`; a client can cancel a request; `meetingLink` write refused). Deployed to `baymax-148da-default-rtdb` on 2026-10-16 with the user's approval (syntax accepted; anonymous read/write of the nodes returns 401); semantics still never run in the emulator or with a signed-in user.
- **Not verified:** nothing run on a device or with a real sign-in; accept/decline/registration were exercised only against an in-memory database; registration needs Email/Password sign-in enabled (it is) and creates real Firebase accounts when a person submits the form.

### 2026-10-15 — Merged Module 15 (Payment Integration): payment screen, hold, receipt (TEST MODE gateway)

- **What a member sees (FR-1 to FR-7, FR37.1 to FR37.8, mockup M37):** Confirm booking now *holds* the chosen time for 10 minutes and opens `screens/specialists/payment_screen.dart`: read-only appointment card (name, role badge, date, time, type), a countdown, method tiles (Credit/Debit Card default, JazzCash/EasyPaisa, Pay at Clinic), the method's fields, "Save card for future payments" (off by default), order summary (consultation fee, platform fee shown even at PKR 0, total = sum), padlock in the app bar, and "Pay PKR X" which is disabled until everything is valid, shows a loading state and ignores a second tap. Success opens `payment_success_screen.dart` (appointment + payment details, transaction id). Only then is the booking confirmed and the notification sent (FR36.8). Leaving the screen, or the hold running out, gives the time back; an unreleased hold expires on its own and other people can take the slot over.
- **Checks:** card = 16 digits that pass the check-digit test, Visa or Mastercard only, expiry a real month and not in the past (good through the last day of the month), 3-digit CVV, cardholder name; wallet = provider + Pakistani mobile number; saved card = fresh CVV only. A fee that cannot be read blocks payment (FR37.2).
- **THE GATEWAY IS A TEST ONE, NOT JAZZCASH.** The scope names JazzCash with server-side calls and says card numbers/CVV are never stored or transmitted (NFR-S9, CI-5). There are no merchant credentials, no server holding a secret key, and I did not guess JazzCash's API. `services/payment_gateway.dart` defines `PaymentGateway`; `SandboxGateway` accepts only the published test cards (4242 4242 4242 4242 Visa, 5555 5555 5555 4444 Mastercard succeed; 4000 0000 0000 0002 is declined; any other card is refused with a hint, so a real card cannot be "charged" and nothing is sent anywhere). Wallets succeed unless the number ends in 0000. The screen says "Test mode" and the receipt says "Test payment: no money was taken". Records carry `mode: sandbox`.
- **What is stored:** `appointments/{id}/payment` = transaction id, method, status (`paid` / `pay_at_clinic`), fee, platform fee, total, gateway reference, brand + last four digits only, mode, time. Never a card number, CVV or cardholder name. Saved cards: `users/{uid}/savedCards` = gateway token, brand, last four, expiry only. Platform fee: `config/payments/platformFee` (nobody can write it from a client; missing = 0).
- **Rules (`database.rules.json`, updated and deployed to `baymax-148da-default-rtdb` on 2026-10-15 with the user's approval; anonymous read/write of the new nodes return 401):** appointment created as `pending_payment` with a hold of at most 10 minutes; slots are now `{appt, holdUntil}` and an expired hold can be taken over; confirming needs a payment record whose amounts match the fee and the current platform fee, inside the hold; clients may write only `mode: sandbox` payments. **To go live:** build the server that calls JazzCash, let only it write `payment` and confirm (Admin SDK), and delete the client write rules for `payment`, `status` confirm and `holdUntil`. Until then anyone can mark their own booking as paid, which is harmless only because no money moves. Rules syntax passes `firebase deploy --dry-run`; semantics are untested against the emulator.
- **Portal:** held bookings are invisible to specialists (list, dashboard counts, detail, notes, status all 404 them), and an unknown status is no longer read as "confirmed". The list and detail show Paid (test) / Pay at clinic.
- **Not done:** refunds (the cancel dialog says refunds are not automatic once a live gateway exists), payment history screen, receipts by email/PDF, deleting a saved card from the UI (`PaymentService.deleteCard` exists), 3-D Secure, a server-side hold sweeper (expiry is enforced by the rules and the clients).
- **Tests:** `test/payment_test.dart` (44: card/wallet checks, the test gateway, `PaymentService.pay` incl. decline, expired hold, amount mismatch, double submit, charge-then-write failure, save-card only when ticked, and the payment/success screens); `consultation_test.dart` updated for hold-then-pay. App total 341 pass; portal 28 pass.
- **Not verified:** nothing run on a device or with a signed-in user against the live database; the rules' slot/payment cross-checks have never run in the emulator.

### 2026-10-15 — Merged Module 14 (Online Consultation): app screens + separate specialist web portal

- **Where:** the app work is in `app/` (the working tree; `Baymax-implementation/app` is an older snapshot and was **not** touched). The specialist web portal is a separate project at `~/Downloads/baymax-portal/` (`server/` Express, `web/` Next.js) that uses the same Firebase project `baymax-148da` but shares no code or packages with the app.
- **App (FR-1 to FR-3, mockups M35 + M36):** `screens/specialists/specialists_screen.dart` is now the real Find-a-specialist screen (search, Doctor/Nutritionist/Trainer tabs, Available today / Top rated / Emergency filters that combine, "24 Nutritionists Found" count, cards with rating, next open time, Book). `book_appointment_screen.dart`: date strip (days off crossed out), time slots, Video call (recommended, default) or Chat only with its own fee, consent ticks (health summary, 7-day diet log, 30-day workouts; all off by default), 500-character note, booking summary, Confirm. `my_appointments_screen.dart`: Upcoming / Past, detail with meeting link (copy), the specialist's notes and prescription, Cancel. Reachable from the Find-a-specialist app bar, the menu ("My appointments"), the chatbot's "Book a Consultation" chip (used to say "coming later") and the booking confirmation notification (new `appointment` notification type).
- **Rules and logic:** `models/consultation.dart`, `services/consultation_rules.dart` (pure: slots in the specialist's time zone, 15-minute lead time, filters, booking checks, join window 5 minutes before to end, cancel only before the start), `services/consultation_service.dart` (Realtime Database).
- **Booking is atomic:** one `update()` writes `appointments/{id}`, `slots/{specialistId}/{startMs}` and `users/{uid}/appointmentIds/{id}`. The slot key can only be created once, so two people cannot book the same time; the second gets "That time was just taken".
- **Database rules** (`database.rules.json`): new `specialists`, `slots`, `appointments` (+ `.indexOn`), `users/$uid/appointmentIds`, inbox type `appointment`. A member can create an appointment only for themselves, with the fee, duration and role checked against the specialist's profile, can cancel only their own confirmed future booking, and cannot write the specialist's notes. **Rules deployed to `baymax-148da-default-rtdb` on 2026-10-15 with the user's approval (the server accepted the syntax; anonymous read and write of the new nodes return 401). They have NOT been run against the emulator or with a signed-in user; the expressions that cross-check the slot against the appointment (`newData.parent()...`) need that check before anyone relies on them.**
- **Deviations from the scope (all deliberate, all in the portal README too):** specialists with no reviews are listed as "New" (the scope hides them, which would hide everyone, since there is no review feature); payment is Module 15 (built afterwards, see the entry above it); meeting rooms are Jitsi links (`MEETING_BASE_URL`, public server may ask the host to sign in), chat-only opens the same room with camera and microphone off; no `url_launcher` package was added (needs your OK), so the app copies the link instead of opening it.
- **Not built:** specialist editing of workout/diet plans (FR-5: plans are derived, not stored); the doctor's risk alerts, diet reviews, posture flags and notification bell (need AI-engine data); an in-app local reminder before an appointment.
- **Tests:** `test/consultation_test.dart` (44 tests: availability parsing, slots across time zones, filters, booking rules, join/cancel windows, the three screens); `ui_test.dart` updated (drawer entry; old "coming in a later release" test replaced). Portal: 24 API/rules tests (`server/`, `npm test`) with an in-memory database.
- **Not verified:** nothing was run on a device or against the live database; no real specialist account exists yet (create one with `server/scripts/create-specialist.js`, see the portal README); the web app's Firebase Web config has to be registered in the console first.

### 2026-10-13 — Module 3: exercises chosen from the user's body parameters; exercise dataset curated

- **Pushed earlier today:** commit `d15ec66` on `Amna's-work` (branch `main` untouched) with everything up to the calorie optimiser. The trained food model (`food_classifier.tflite`) and a plot of scraped images were deliberately **not** pushed (public repo, Kaggle licence unverified); the snapshot copy of this file had the registration numbers removed. The work below is **not pushed yet**.
- **Dataset curated** (`ml/exercise_curation/curate_exercises.py`, reproducible): from free-exercise-db (Unlicense, 876 exercises, 1 MB, downloaded from GitHub into a scratch folder) 188 no-equipment entries were reviewed by name and instruction text; 41 were kept. Left out: anything needing a bar, bench, machine or partner, expert moves, athletic drills; the dataset's own instructions were **not** used (e.g. "Smith machine bar", "Split Squats" that is really a jump, "jump as high as possible"). Kept: exercise identity, muscles, mechanic, difficulty; **all technique cues are team-written**. Library is now 73 exercises (32 original + 41 curated: push 5, legs 2, core 8, cardio 2, mobility 24); the originals keep their energy values and sources.
- **Energy values are not invented:** each curated exercise uses the MET of the closest movement class already in the library (Compendium codes 02056, 02022, 02024, 02030, 02101, 02057, 02020, marked `*`). **Team-assigned fields (not in the dataset, pending trainer/physio review):** `joints`, `position` (standing/seated/floor), `complexity` (1-3), `equipment`; these were also added to the 32 originals.
- **Selector** (`services/exercise_selector.dart`, plugged into `PlanGenerator`): the existing safety rules still decide what is *allowed*; the selector then *ranks* by the person's inputs: capacity (activity level, minus 0.25/0.5 for age 50+/65+ and BMI 30+/35+) vs exercise level (too hard costs 2.0 per level, too easy 0.8); goal (weight loss favours MET, muscle gain favours push/legs/back and compound moves); joint load by BMI/age; floor-getting-up penalty (age 65+ or BMI 35+); coordination (age 60+); variety across the week; a small variant-based tie-break so Regenerate changes the plan. Gender is deliberately not used for exercise choice. Every exercise shows a reason (card and detail screen), and the detail screen shows needed equipment.
- **Personalised cool-down:** after each session up to two static stretches for the body regions actually worked (muscle labels mapped to regions; dynamic moves excluded).
- **Found while checking:** the dataset's labels are inconsistent (Quads/Quadriceps, Abs/Core), so a region map was added. Users with similar restrictions (e.g. BMI 30 vs 31, both low capacity) still get near-identical weeks, because few low-impact, level-1 exercises exist; the profile also has no injury or joint-pain question, so the app cannot adjust for those.
- **Tests:** 163 pass (new: 20 in `test/exercise_selector_test.dart`, including a 400-random-people property test that cardiac/hypertension/BMI/age safety rules still hold on the larger library, library integrity and wording checks, scoring behaviour, determinism, variety, reasons, cool-down). `flutter build apk --debug` succeeds.
- **Firestore seeded (user approved):** `node Baymax-main/tools/seed_firestore.js <app>/assets/data/exercises.json --collection exercises` -> 73 exercises (56 matched to free-exercise-db, 17 team-written), catalogue version 1791880952. Anonymous read/write of `exercises`, `meta/exercises` and `foods` still return 403. Sources screen updated (exercise library + how exercises are chosen). Not reviewed by a trainer or physiotherapist.

### 2026-10-13 — Module 3 FR-4: adaptive calorie-target optimiser (algorithm; NOT Gradient Boosting)

- **Why not Gradient Boosting:** it needs measured daily energy expenditure. The only suitable source, the IAEA doubly-labelled-water database (dlwdatabase.org), is free but released on request (an application form reviewed by its management group), so it cannot be downloaded today. No model was trained on made-up or unsuitable data (rule 2). The scope wording "optimize calorie targets using Gradient Boosting" is therefore **not met literally**; discuss with the supervisor (reword FR-4, or apply to the IAEA).
- **What was built** (`services/calorie_optimizer.dart`, pure Dart): from the user's own weigh-ins and food logs (last 28 days) it estimates maintenance calories by energy balance: mean logged intake − (least-squares weight slope × 7,700 kcal/kg). That is combined with the Mifflin–St Jeor × activity estimate by a normal–normal Bayesian update (prior sd 10% of the formula, observation sd from the slope's standard error plus 10% logging error), so noisy weights count for less. It plugs into the existing `CalorieOptimizer` seam (`AdaptiveCalorieOptimizer`); the target is rebuilt with the same minimum-intake floors (1,200 F / 1,500 M, at least BMR on a deficit) and the underweight no-deficit rule.
- **Safeguards:** needs >= 4 weigh-ins over >= 14 days and >= 10 "fully logged" days (a day with under 60% of BMR logged is ignored); data share capped at 70%; may raise the formula by <= 15% and lower it by <= 10%; changes under 100 kcal ignored; **if the logs imply a need more than 30% from the formula the data is rejected** (almost always unlogged meals); **off for under-18s and for reported heart disease or diabetes** (formula target kept). Found by simulation: someone logging only 60% of their food would otherwise have been given a lower target (1,898 -> 1,744 kcal); the plausibility guard and the tighter decrease limit were added because of it.
- **App:** new weight log (`services/weight_service.dart`, `users/{uid}/weights/{date}`); `UserSession` keeps `calorieEstimate`, rebuilds the plan (target, macros, meals) when it changes, refreshes in the background after sign-in, and `logWeight()` also keeps the profile weight current. New screen "Your calorie target" (Nutrition Plan -> "How is my target worked out?", and Profile): target, how it was worked out in plain words, a checklist of what data is still needed, weight check-in and a weight/trend chart. Sources screen entry added with the equation sources (Mifflin 1990; Wishnofsky 1958; Hall 2011) and the honest list of team-chosen assumptions.
- **Tests:** 143 pass (new: 19 in `calorie_optimizer_test.dart` using simulated people with measurement noise, 7 in `calorie_target_screen_test.dart` including that the plan's target, macros and meals follow the estimate and that a diabetic user keeps the formula). `flutter build apk --debug` succeeds.
- **Database rules:** `weights` node added to `database.rules.json` (kg 20-400, one entry per date). Deploy approved by the user. The first attempt failed (this Mac could not resolve Firebase host names, a local resolver problem; nothing changed in the cloud); **retried later the same day and deployed successfully**. Anonymous read and write of `users/x/weights` and of the root return 401 Permission denied. Signed-in reads/writes still unverified (need a real login).
- **Not verified:** only simulated people, no real users; behaviour against the live database; on a device. The 7,700 kcal/kg constant, the 10% uncertainties, the 28-day window, the 60%-of-BMR rule and all limits are team choices, not published values.

### 2026-10-13 — Modules 11 and 14: gamification, leaderboard, roles, reminders, inactivity alerts

User approved: deploying new Realtime Database rules, and the notification packages. **Not approved, so not done:** the encryption packages (M14 FR-1) .

**Module 11 (Community Ranking & Gamification)**
- **Activity log:** "Mark as completed" on the Workout screen (any day of the current week up to today, with Undo) writes `users/{uid}/activity/{date}`; this is the first place the app records that a workout actually happened.
- **FR-1 fitness score** (`services/gamification.dart`): 50% workouts done / planned days so far this week, 25% days with food logged, 25% logged days within ±15% of the calorie target; weights renormalised when no planned day has passed. **These weights, the 15% window and the level thresholds are team design choices with no external source** (stated on the Sources screen).
- **FE-5 level** Beginner < 40 ≤ Intermediate < 70 ≤ Advanced (average of recent weekly scores). **FR-3 badges:** 8 rule-based badges over the last 28 days (first workout, 3/7-workout streak, full week, 3/7-day logging, on target x3, score 80+); earned badges are stored in `users/{uid}/badges` and never taken away.
- **FR-2 weekly leaderboard** (`leaderboard/{ISO week}/{uid}`): opt-in; shares only display name, score, workout count, logging days. Scores are computed on the phone, so they are **not tamper-proof** (needs server-side scoring to be trustworthy).
- **FR-4 K-Means:** implemented (k-means++ seeding, fixed seed, k=3 on score/workouts/logging days) and unit-tested on synthetic cohorts, but only used when the leaderboard has **15 or more** participants; with fewer, the score thresholds are used and the screen says which method produced the levels. Not trained on or validated with real users (there are none yet).
- Screens: new Community & progress screen (score bars, streaks, badges, leaderboard, join/leave) and Reminders & community settings; dashboard shows the weekly score card, the working Leaderboard tile and an inactivity banner.

**Module 14 (Secure Data Management & Smart Alerts)**
- **FR-3 workout reminders:** local notifications on planned workout days at a time the user picks (off by default; permission requested on enabling). Packages added: `flutter_local_notifications`, `timezone`. Android: core-library desugaring, `RECEIVE_BOOT_COMPLETED` and the plugin's receivers; inexact alarms (no exact-alarm permission). Times are scheduled as UTC instants and rebuilt at each launch (no timezone database). Notification text carries no health data. Reminders are cancelled on sign-out.
- **FR-5 inactivity:** inactive = >= 3 days since the last workout AND >= 1 planned workout day missed (rest days never count); dashboard banner plus one optional "we miss you" notification.
- **FR-2 role-based access:** `UserRole` (member, doctor, nutritionist, trainer, admin) read from `roles/{uid}`, which the rules make writable by nobody from the app (set in the Firebase console). Today the rules still give no one access to another user's data: clinician-patient assignment belongs to Module 13.
- **Not done:** **FR-1 AES encryption** (needs the encryption packages and a key design: a key stored on the phone cannot be recovered after a reinstall; data is also validated by field-level rules that encrypted fields would defeat); **FR-4 injury-risk alerts** (needs Module 9); **FR-6 FCM push** (needs `firebase_messaging` and a server to send; local notifications cover reminders only).

**Database rules** (`database.rules.json`, deployed to `baymax-148da-default-rtdb`, syntax validated by the CLI): new `users/{uid}/activity|badges|settings` with field validation, `roles/{uid}` (own read, no writes), `leaderboard/{week}/{uid}` (any signed-in user reads, only the owner writes, score 0–100, `.indexOn score`). Verified with curl: anonymous read and write of every new node and of the root return 401 Permission denied. **Not verified:** signed-in writes and reads (needs a real login); if the app shows "The database refused access" after marking a workout, paste the error. Previous rules saved as a scratch copy only.

**Tests:** 118 pass (new: 26 in `test/gamification_test.dart` covering ISO weeks, score maths, streaks, badges, levels, K-Means, inactivity, reminder times, roles; 8 in `test/community_test.dart` for the snapshot builder, both new screens, settings model). `flutter build apk --debug` succeeds with the notification setup. **Not verified on a device:** notifications actually firing (permission prompt, battery optimisation, reboot), the whole flow against the live database, iOS (cannot be built on this Mac; the plugin needs the standard AppDelegate notification-delegate setup there).

### 2026-10-13 — Module 7: trained food model integrated (experimental, gate not passed)

- **Kaggle result** (`ml/food_classifier/results_2026-10-12/`): EfficientNetV2-B0, 22 classes, held-out test (2,317 images) **top-1 92.6%, top-3 98.6%**, TFLite agrees with the trained model on 100%. Per source: Food-101 93.6%, Kaggle set 1 85.2% (182 imgs), Kaggle set 2 76.2% (42 imgs). **Shipping gate FAILED**: `aloo_gobi` recall 65% (13/20) and `paratha` 65.4% (17/26) are below the 70% per-class bar, so the notebook saved the file as `..._CANDIDATE.tflite` with `ship_recommended: false`. Weakest others: roti 75%, butter_chicken 81%, haleem 84%. Label-noise pass: 0 images removed. Recommended min confidence 0.30.
- **Independent check:** the file was re-run in Python on the 224 Pakistani test images with a different resize (box filter): 81.7% vs 83.5% in the notebook, so results are slightly sensitive to the resize method; the app's own resize path is untested on a device.
- **Integration:** files copied to `assets/models/food_classifier.tflite` (11 MB) + `food_classifier_labels.json` (the app picks them up automatically). `food_image_classifier.dart`: new `FoodModelInfo` (labels, input size, min confidence, gate result, weak foods = recall < 70%); **a model with `ship_recommended != true` is loaded only in debug/profile builds; release builds ignore it and fall back to manual food selection** (so the "no model ships unless it passes its gate" rule is enforced by the app); phone-photo rotation is now baked in before inference. Scan screen: "experimental model" banner, and "Less reliable for this dish" on aloo gobi / paratha suggestions. Sources screen: new entry with the real numbers, the Kaggle caveat, and the failed gate.
- **Tests:** 84 pass (new `test/food_model_test.dart`: metadata, weak foods = {aloo_gobi, paratha}, experimental flag, all 22 labels exist in the food catalogue). `flutter build apk --debug` succeeds with the model packaged. **Not verified on a device**: the TFLite model has not been run by the Flutter plugin on a phone.
- **To pass the gate:** more distinct aloo gobi / paratha photos (set 2 gives only ~100 distinct pictures per dish), ideally the team's own phone photos (`pakistani_photos_template.zip`), then re-run the notebook. Do not set `ship_recommended: true` by hand without the team deciding to accept the weaker bar.

### 2026-10-12 — Module 7: final Kaggle package built (Food-101 + Kaggle "Pakistani Dishes")

- **Output:** `food_dataset_final_kaggle.zip` (450 MB; replaces `food_dataset_kaggle.zip`) + `module7_food_model_kaggle.ipynb`. 22 classes, 13,167 images (8,472 train / 4,695 validation): the 13 Food-101 foods + 10 Pakistani/South-Asian dishes mapped to catalogue ids (aloo_gobi, bhindi, butter_chicken, chicken_biryani, chicken_tikka, haleem, paratha, roti [chapati], samosa [also in Food-101], tea_milk [chai]).
- **Findings about the Kaggle sets** (`~/Downloads/archive`, folders `dataset/` 14 x 100 and `pakistani_dishes_dataset_2/` 12 x 765): set 2 is the same photos repeated with rotation, zoom, flips and smeared edges (about 100-150 distinct pictures per dish, not 765). Random splitting would have put copies of one photo in train and test. Set 1 has near-duplicates too. Folder labels are the scrapers' and are noisy: the "Chai" folder of set 2 is mostly bubble tea; "chicken tikka" contained curries, pizza, samosa.
- **Method** (`ml/food_classifier/build_final_dataset.py`): MobileNetV2 fingerprints over 8 views (4 rotations x mirror), average-linkage clustering per food (single linkage chained different photos into blobs of 500+), one picture kept per cluster (first source preferred), pictures matching a Food-101 image removed, same picture under two foods removed, 60/20/20 split by unique picture with test/selection taken from the clean originals (set 1) where possible, final twin filter on the saved thumbnails (validation pictures with sim >= 0.85 to a training picture dropped). Check after the build: max similarity of each validation picture to its nearest training picture is 0.84 or lower, 0 pairs >= 0.85.
- **Hand review:** `review_sheets.py` + `exclude_md5.txt`: all 153 chai and all 110 tikka images were looked at; 67 + 20 pictures (and their copies) removed. The other eight dishes were checked on a 24-image sample each (mostly correct; some augmented-looking images remain). `preview/<dish>.jpg` in the zip shows a sample.
- **Not used (no catalogue food):** paratha_roll, ras_malai, bbq, brownie, fried_rice. omelette/french_fries from the Kaggle set 1 skipped (Food-101 covers them). Adding ras_malai/paratha_roll to `foods.json` (with a sourced calorie value) would let them be trained.
- **Notebook changes:** reads `half`/`source`/`grp` columns; prints and stores test top-1 per source (`test_top1_by_source`), because Kaggle-web accuracy is not phone-camera accuracy; labels JSON lists the sources. Quick-mode run on the final package passes end to end (untrained model correctly rejected by the gate). Not run on a GPU.
- **Limits:** Pakistani dishes have only 52-82 training and 35-55 validation (about 17-28 test) pictures each against 600 for Food-101 foods (class weights compensate); the 70% per-class recall gate is therefore a rough check for them. Licence of the Kaggle sets is **unverified** (ATTRIBUTION.md); the images look web-scraped. Do not put the zip in the public GitHub repo. The user's own phone photos (`pakistani_photos_template.zip`) remain the right final test.
- Reproduce: `python build_final_dataset.py --base <extracted food_dataset_kaggle> --extra kaggle_pakistani_dishes_1=<archive/dataset/dataset> --extra kaggle_pakistani_dishes_2=<archive/pakistani_dishes_dataset_2/food_dataset_2> --out <dir> --exclude exclude_md5.txt --min-unique 80 --cache <fp.npz>` (run from `ml/food_classifier`, needs the `ml/.venv` TensorFlow + scipy).

### 2026-10-12 — Datasets moved out of the project

- `ml/data/cdc_diabetes_health_indicators.csv` (13 MB, the only dataset inside `app/`) moved to `~/Downloads/baymax_datasets/`. Retrain Module 2 with `ml/.venv/bin/python ml/health_classifier/train.py --csv ~/Downloads/baymax_datasets/cdc_diabetes_health_indicators.csv`. Datasets were never bundled in the app (pubspec assets: foods.json, exercises.json, models only); the packaged-app size is unchanged. Remaining weight in `app/`: `build/` 2.3 GB and `ml/.venv` 1.4 GB (both regenerable, git-ignored). The Kaggle zips live next to `app/`, outside it.
- Pakistani Kaggle dataset: downloaded by the user into `~/Downloads` (not yet inspected). The Roboflow candidate could not be found by the user.

### 2026-10-12 — Module 7: notebook now trains on the team's own Pakistani photos

- `module7_food_model_kaggle.ipynb` (and its copy `ml/food_classifier/train_kaggle_notebook.ipynb`): new section 1a reads an optional second Kaggle input `custom_photos/<catalogue_id>/<session>/*.jpg`. It fixes phone rotation, removes duplicates (exact and, across sessions, near-identical), splits **by session** ~60/20/20 (no near-identical photos on both sides), validates folder names against the 97 catalogue ids ("did you mean...?"), and trains a dish only if it has 100+ usable photos and enough sessions for 15+ test photos; other dishes are reported as NOT TRAINED. Same shipping gate for all classes. Writes `custom_photos_report.json`; the labels JSON records which team photos were used.
- Tested locally in quick mode on the real cleaned Food-101 data plus synthetic photos: a 128-photo/8-session dish trained (14 classes), a 40-photo dish and a 117-photo dish with only 13 test photos were skipped with reasons, HEIC counted and skipped, a misspelled folder name stopped with a suggestion, and with no custom folder the result is identical to before (13 classes, 7,800 train). Not run on a GPU; real accuracy still unknown.
- New: `pakistani_photos_template.zip` (empty folders for 25 Pakistani dishes + README). `PAKISTANI_PHOTOS.md` rewritten for this layout.
- No Pakistani dataset was downloaded: DeshiFoodBD (CC BY 4.0, Bangladeshi, 4.2 GB, only biriyani/nehari overlap) awaits a decision; the Kaggle/Roboflow candidates need a login and a class/licence check.

### 2026-10-12 — Module 7: search for Pakistani food datasets (nothing downloaded)

- **Correction:** the 2026-10-09/10 notes say no Pakistani-dish dataset exists. A web search found several *candidates*, so that claim was too strong. None has been downloaded or checked image-by-image.
- Candidates, all **unverified** (class lists, licences or image counts not confirmed from the primary page unless stated): Kaggle "Pakistani Dishes Dataset" (`useractivated/dataset`; ~14 classes x ~100 images per a search snippet; page could not be read); Roboflow `calgenie/pakistani_food` (CC BY 4.0 per search snippet; object detection; classes not seen); DeshiFoodBD (Mendeley, **Bangladeshi**, 5,425 images, 19 classes incl. biriyani and nehari, CC BY 4.0 confirmed on the page); GitHub `ahsantahseen/Pakistani-Food-Recognizer` (6 dishes x 180 images, scraped + own photos, no licence, dataset not linked). Khana (Indian) licence unconfirmed here; earlier noted CC BY-NC-ND 4.0.
- Rule 6 applies: ask before downloading. Web-scraped images with no stated licence are not to be used in training.

### 2026-10-12 — Status check; Module 3 FR-4 reassessed; Module 7 photo-collection guide

- **Re-ran `flutter test`: 79 passing.** Modules 1, 2, 3 (except FR-4), 7 (text), 8, 12 behave as logged; no code changed.
- **Module 3 FR-4 ("optimize calorie targets using Gradient Boosting")** is about the daily calorie *target*, not workout energy. The WEEE dataset (indirect calorimetry during activities, 17 people) does not measure daily energy needs, so it is **not** a source for FR-4 (earlier note in this file calling it a Module 3 candidate applies only to workout kcal). The only measured source for daily energy is IAEA doubly-labelled water (by application). With no valid data, no model is shipped (rule 2); the rule-based target stays. Decision for supervisor: reword FR-4 or wait for the IAEA data.
- **Module 7:** added `ml/food_classifier/PAKISTANI_PHOTOS.md` (dish list, folder layout, photographing and session-split guidance). The Kaggle notebook does not yet read a `--custom` folder (only `train_kaggle.py` does) — to add once photos exist.

### 2026-10-12 — Documentation, GitHub and notebooks (housekeeping record)

- **GitHub:** repo `laibaAttique/Baymax-implementation` (public; was empty). Branches **`main`** and **`Amna's-work`** were pushed at commit `d4faeb9` (223 files: `app/`, `backend/`, README, `.gitignore`). Git forbids spaces in branch names, so "Amna's work" became `Amna's-work`. Pushed from a clean snapshot (`Baymax-implementation/` next to `app/`), with Firebase config files, `.env`, Word documents, training data and registration numbers excluded. Pushing used the user's own `gh` login via a per-command credential helper; no credentials were shared. Because the repo was empty, `Amna's-work` briefly became the default branch; changing it needs an admin (Laiba). **GitHub is now behind the local work** (everything from 2026-10-10 onward: ML cleaning/training scripts, both notebooks, README/PROGRESS updates, minimum-confidence change) — re-sync and push when needed. A zip of the snapshot (`Baymax-implementation.zip`) also exists.
- **Packages and notebooks created:** `gym_dataset_kaggle.zip` (cleaned Module 3 data + scripts), `food_dataset_kaggle.zip` (cleaned Module 7 images, 452 MB), `module3_calorie_model_kaggle.ipynb` (clean → validate against the Compendium → train → safety gate; run on Kaggle by the user: refused to export, as designed), `module7_food_model_kaggle.ipynb` (EfficientNetV2-B0, shipping gate; not yet run on a GPU).
- **`CLAUDE.md`** added (project memory for future sessions: layout, commands, architecture, rules, gotchas). Top status table of this file refreshed.

### 2026-10-12 — Accuracy-first Module 7 notebook; Module 3 data findings

- **Module 7:** built `module7_food_model_kaggle.ipynb` (also `ml/food_classifier/train_kaggle_notebook.ipynb`): EfficientNetV2-B0, two-stage fine-tuning, label-noise pass, held-out test set (half of the clean validation images, never used for decisions), flip-averaging check, confidence-threshold table, float16 TFLite export, TFLite-vs-Keras parity check and a **shipping gate**. Verified in quick mode on the real cleaned data (all cells, TFLite export 11.7 MB, only built-in ops, 100% parity, gate correctly rejects an untrained model, label-noise retraining branch exercised). Real accuracy is unknown until the Kaggle run. App: `minConfidence` now comes from the model's JSON (`recommended_min_confidence`).
- **Module 3:** the gym dataset's calories are a linear function of average heart rate × duration (R² 0.99) and the average heart rate is identical for every workout type (≈143 bpm for yoga and HIIT), so it cannot teach workout type; no script can fix that. Candidate legitimate data: **WEEE** (Zenodo 6420886, CC BY 4.0, 652 MB, 17 participants, indirect-calorimetry ground truth with activity type, MET and demographics). Not yet downloaded or evaluated; a model from it would be accepted only if it beats the Compendium under leave-one-person-out validation. IAEA doubly-labelled-water remains the source for daily energy.

### 2026-10-10 — Module 7 dataset cleaned and packaged for Kaggle

- `foodarchive.zip` (5.7 GB, ZIP64) is the Kaggle copy of **Food-101**. Cleaned with the new `ml/food_classifier/clean_images.py`: 13 catalogue foods (from 17 Food-101 dishes), **12,049 images — 7,800 train / 4,249 validation**, 384 px. The official test images are the validation set; 13 duplicates, 7 train/validation leaks and 2 cross-class lookalikes removed. Package: `food_dataset_kaggle.zip` (452 MB) with images, split, report, scripts and README. `train_kaggle.py` gained `--prepared` to read it.
- Verified from a fresh unzip: all 13 labels exist in the food catalogue, no missing or shared files across splits, script trains and exports a TFLite model that matches the trained model on 100% of images (trial accuracy is chance level by design — no pretrained weights, 1 epoch).
- **Findings:** the training photos contain mislabeled images (Food-101's own warning; visible in a sample) that no duplicate check can find, and the dataset has **no Pakistani dishes**, so biryani/karahi/nihari/haleem can only be recognised after adding your own photos (`--custom`).
- **Next:** run the Kaggle training, check per-class accuracy, add Pakistani photos, copy the two output files into `assets/models/`, device-test.

### 2026-10-10 — Module 3 dataset cleaned; it fails a physiology check, so no model is shipped

- Downloaded dataset (Kaggle *Gym Members Exercise Dataset*, `archive.zip`) profiled and cleaned with the new `ml/calorie_model/clean_data.py`: 973 → 950 rows (23 sessions with average heart rate above the maximum removed; no other defects). Packaged for Kaggle as `gym_dataset_kaggle.zip` (cleaned CSV, cleaning report, scripts).
- **Finding:** the data contradicts published energy costs and looks synthetic — implied MET ≈ 10 for every workout type (workout type explains 0.4% of variation); 0 of 232 yoga sessions are physiologically plausible. A Gradient Boosting model on it predicts ≈765 kcal/hour for yoga and HIIT alike. Details in `ml/README.md` section 4 and the report inside the zip.
- **Script change:** `ml/calorie_model/train.py` now has a physiology gate. The previous rule ("export if it beats the MET baseline") would have shipped this wrong model; it now also requires per-type predictions within 0.5×–2× of the Compendium and monotonic in body weight. On this data it correctly refuses to export. The app is unchanged (workout calories remain Compendium-based).
- **Open decision:** use the dataset only as a pipeline demo, or obtain measured-energy data (IAEA DLW by application) for a legitimate Module 3 model.

### 2026-10-09 — Phase 2 started: model training pipeline (Modules 2, 3, 7)

Everything is in `app/ml/` (see `ml/README.md` for dataset links, steps and licenses). The app uses each model automatically when its file is in `assets/models/`; without the file it keeps the rule-based behaviour.

| Model | Status |
|---|---|
| **Module 2 — Logistic Regression** | **Trained here** on the CDC Diabetes Health Indicators data (253,680 adults). Exported as JSON (used by the app) and TFLite (see below). |
| **Module 3 — Gradient Boosting** | Training script + Dart evaluator + plan integration done and unit-tested against a synthetic fixture. **Not trained:** the Kaggle dataset needs a login. Exports only if it beats the MET baseline. |
| **Module 7 — MobileNetV2 → TFLite** | Kaggle training script, class map, on-device TFLite runner and scan-screen flow done. **Not trained:** needs a GPU and ~5 GB of images. |

**Module 2 results (20% held-out, 50,620 people)** — reported honestly:
- Six-class accuracy **40%**, macro-F1 **0.40**. The categories cannot be separated well from BMI, age, sex and activity alone (the "At-Risk" group is mostly people with high blood pressure/cholesterol).
- The risk ranking is moderately useful: **ROC-AUC 0.76 (heart disease), 0.73 (diabetes)**.
- Risk flags use thresholds that mark only the top ~15% of people (about 2.5× the base rate of true cases).
- In the app (`HybridHealthClassifier`): the rule engine always decides first; the model shows a statistical-risk estimate on the classification screen and only upgrades someone to **At-Risk** when nothing is reported and their risk is in the top ~15%. It never assigns Cardiac or Diabetic. Verified by tests: reported conditions are never overridden, and the hybrid is never less cautious than the rules alone.
- Dart output matches scikit-learn to 1e-9 on exported test vectors.

**Export verification (done):** `health_classifier.tflite` (2.6 KB) matches scikit-learn to 1.4e-6. The food pipeline was run end to end locally on synthetic images (class mapping → tf.data → training → float16 TFLite export → inference): it exports a 4.4 MB model whose answers agree with the Keras model on 100% of images. The training script now fails if that agreement drops below 95%, so a bad export cannot be shipped silently. (The synthetic run says nothing about real accuracy; that needs the Kaggle run.)

**Data caveats found while checking sources:** the survey year is inconsistent (UCI's summary links the 2014 BRFSS page, the Kaggle copy says 2015), so the app says "CDC BRFSS survey" without a year. The UCI license wording could not be confirmed. The model is US data and not validated for South Asians.

**Dataset findings:** no Kaggle/UCI dataset of Pakistani dishes exists (closest: Indian sets, Khana — CC BY-NC-ND 4.0 — and a Roboflow detection set). The only authentic measured-energy dataset (IAEA doubly-labelled water) is by application. The "Indian Food Images (Kaggle)" dataset I first planned to cite could not be found, so it is not listed.

**App changes:** `HealthRiskModel` + `HybridHealthClassifier`; statistical-risk card on the classification screen; `GradientBoostingModel` / `WorkoutCalorieModel` with "Calories (AI)" labelling; `TfliteFoodClassifier` (tflite_flutter) with top-3 suggestions and confirmation in the scan screen (`FoodTextLog` accepts pre-selected foods); Sources screen entry for the ML model. 79 tests pass; Android build compiles with the TFLite plugin.

**To finish Phase 2:** (1) run `ml/calorie_model/train.py` on Kaggle with the gym dataset; (2) run `ml/food_classifier/train_kaggle.py` on Kaggle with Food-101 + Indian sets + your own Pakistani photos; (3) copy the outputs to `assets/models/`; (4) device-test; (5) consider applying for the IAEA data for a proper daily-calorie model.

### 2026-10-09 — Exercise library made dynamic (Firestore) and sourced

**Dynamic.** The 32 exercises are no longer hardcoded in Dart. They live in Cloud Firestore (`exercises/{id}`, `meta/exercises` version), loaded with the same cache-first, offline-capable mechanism as the food catalogue (`services/catalog_service.dart`, now generic for both). `assets/data/exercises.json` is the offline fallback and the seed source. A downloaded catalogue is only used if it contains the warm-up, cool-down and at least 10 exercises; otherwise the bundled copy is used. The plan generator reads whatever is loaded, so exercises can be corrected or added by re-seeding — no app release.
- Seed: `node Baymax-main/tools/seed_firestore.js <file> --collection exercises|foods` (generalised from the food-only script; uses the developer's `firebase login`).
- `firestore.rules` now also allow signed-in users to read `exercises` (read-only); anonymous access verified → 403.

**Backed by sources**
- **Energy:** Compendium 2024 code per exercise (previous change).
- **Muscles + technique:** 15 of 32 exercises are matched to the open public-domain *free-exercise-db* dataset (Unlicense; 876 exercises). The dataset id and match quality (`exact` / `related`) are stored per exercise and shown on the exercise page. The dataset's cues are written for gym training and in places are unsuitable for prescribed dosing (e.g. plank "hold as long as possible", mountain climbers "explosively"), so muscles come from the dataset while cues are rewritten and labelled "adapted". 17 exercises (brisk walking, marching, jumping jacks, burpees, wall sit, bird dog, calf raise, knee/wall push-ups, …) have no suitable dataset entry and are labelled **team-written, pending professional review**.
- **Safety rules:** cited to verified publications — WHO 2020 physical-activity guidelines, ACSM Guidelines 11th ed., AHA 2024 resistance-training statement (Paluch et al., Circulation 2024;149:e217–e231; it *supersedes* the 2007 statement I had first planned to cite), ADA exercise position statement (Colberg 2016), ACSM hypertension position stand (Pescatello 2004). The Sources screen states plainly that the individual exclusions/caps are conservative team precautions, not quotations, and have not been clinician-reviewed.

**Rule corrections found while checking sources**
- Hypertension: I had removed planks/wall sits on the claim that isometrics "spike blood pressure". Newer evidence does not support a blanket ban, so holds are now **capped at 20 s** with a breathing cue; HIIT and high-impact moves are still removed. Cardiac plans still contain no static holds (precaution pending clinician review).
- Balance training was added at 55+; WHO's recommendation is for adults **65+**, so balance now starts at 65. The high-impact limit stays at 55 as a labelled precaution.

**Tests:** 67 passing (new: exercise data integrity and provenance consistency, JSON round trip, hypertension hold cap, no holds for cardiac, balance from 65).

**Still needed:** a qualified trainer/physiotherapist should review the 17 team-written technique texts and the safety exclusions before release.

### 2026-10-09 — Authentic sources & dynamic data: Firestore food catalogue, Compendium METs, Sources screen

**Request:** everything should be driven by the user's data, be dynamic, and be backed by authentic sources; calories should come from Firestore. Food-image detection needs a trained model (confirmed — it stays in phase 2 behind `FoodImageClassifier`).

**Calories now come from Cloud Firestore**
- `foods/{id}` documents (one per food: name, aliases, per-serving calories/macros, allergen tags, `source`, `fdcId`) and `meta/foods` (`version`, counts). Seeded with `Baymax-main/tools/seed_firestore_foods.js` using the developer's own `firebase login` — no service-account file needed. Re-run it whenever `foods.json` changes; it upserts, deletes removed foods and bumps `version`.
- `services/food_catalog_service.dart`: cache-first. Firestore keeps the catalogue on the device (works offline); one small read of `meta/foods` decides whether to download it again, so a normal app start costs ~1 document read. If Firestore is unreachable and nothing is cached the app falls back to the bundled `assets/data/foods.json`. The food search shows which of the three is in use.
- **Firestore was found wide open** (anonymous read returned 200). `firestore.rules` now allow signed-in users to *read* `foods`/`meta` and nobody to write from the app; everything else is closed. Verified: anonymous read and write → 403.
- Data split: **Realtime Database** = per-user data (profile, food log); **Firestore** = shared read-only reference catalogue.
- Removed the short-lived live USDA search path (backend route, app service, search UI) — the catalogue in Firestore replaces it. `backend/services/usda.js` stays for the verification tool.

**Authentic sources**
- **Exercise energy:** every MET value now comes from the 2024 Adult Compendium of Physical Activities (Herrmann et al., J Sport Health Sci 2024;13(1):6-12), with the Compendium code stored per exercise and shown on the exercise page. Several of my earlier values were wrong and were corrected (push-up 6.0→3.8, plank 3.8→2.8, squat 5.0→3.0, jumping jacks 7.7→7.5, burpees 8.5→7.5, …). Exercises that have no exact entry (marching in place, step-ups, high knees, mountain climbers, shadow boxing, single-leg balance) use the closest listed activity and are flagged `*`.
- **Food nutrition:** each food now carries `source` (`usda` with an FDC id, or `estimate`) and logged entries store that `ref`. **All 97 foods are currently "estimate"** — nothing has been verified against USDA yet. `tools/verify_foods.js` compares ~55 generic foods with USDA FoodData Central and, with `--write`, marks matches within 25% as `usda` with the real values; then re-run the seed tool. **Blocked on: a free USDA API key in `Baymax-main/.env` (`USDA_API_KEY=`).**
- Mixed Pakistani dishes (biryani, karahi, daal…) have no USDA equivalent. The only authentic source is the *Food Composition Table for Pakistan (revised 2001)*, which exists on paper only (listed by FAO/INFOODS), so those stay labelled "estimate".
- **Profile → Sources & methodology** screen lists the reference for every formula and rule with its limits. Citations were checked online; two claims I could not confirm (a 26–45% "moderate-carb" band attributed to the ADA/EASD consensus report; a protein range attributed to the 2016 sports-nutrition position paper) were removed and replaced with verified wording.
- **Decision for the team:** the app uses the international WHO BMI cut-offs. The 2004 WHO expert consultation (Lancet 363:157-163) recommends considering lower cut-offs for Asian populations (≥23 overweight-risk). Not changed — it affects every classification — but worth deciding with the supervisor.

**More dynamic behaviour**
- **Profile → Update my details** re-runs profiling pre-filled with the saved values (step 3 now pre-fills too); BMI, classification, targets and plans recalculate and sync.
- Signup password strength is now computed live (was a fixed mock). Dashboard "Workout Min" renamed "Planned Workout Min" (it is the plan, not tracked activity). Chatbot answers "where do your numbers come from?" and points to the profile editor.
- Still static by design (other modules): emotion banner (M6), Body Transform / Leaderboard / Find Specialist tiles, voice assistant and posture screens (M4/M5), notifications.

**Verification:** 61 automated tests pass (new: Compendium codes/values spot-checked against the published table, provenance fields, catalogue refresh logic). Seed verified by reading Firestore back (97 docs, `meta/foods` version set). Not verified: the app fetching from Firestore on a real device.

### 2026-10-09 — Database moved to Firebase Realtime Database; Profile tab with real user values

**Decision.** User data (health profile, food log) now lives in the Firebase **Realtime Database** instead of Express + MongoDB. The app talks to it directly with the signed-in Firebase user, so the profile/food features no longer need the Node server (this also removes the USB/`localhost` networking problem for those features).

**Data layout** (`users/{uid}/…`)
- `profile` — the health profile (same fields as before + `planVariant`, `updatedAt`).
- `foodLog/{YYYY-MM-DD}/{pushId}` — one node per logged food (`meal, name, quantity, unit, kcal, protein, carbs, fat, source, createdAt`).

**Security** — `database.rules.json` (deployed to `baymax-148da-default-rtdb` with `firebase deploy --only database`):
- Default deny; only the signed-in user can read/write `users/{their uid}`.
- Field-level validation (types, ranges, allowed meals/units/sources, ISO date keys); unknown fields are rejected.
- **The database was found in open/test mode** (anyone with the URL could read/write). It is now locked; anonymous read, branch read and write were each verified to return *Permission denied*.

**App changes**
- `services/realtime_db.dart` (new): database handle, per-user refs, value normaliser, timeout + friendly errors (permission-denied, offline). Offline persistence is enabled so the last data is still available without a connection.
- `services/profile_service.dart`, `services/food_log_service.dart`: rewritten on the Realtime Database (food entries are written with one atomic multi-path update). `UserSession`, screens and the chatbot are unchanged apart from `FoodLogService.delete(entry)`.
- `config/firebase_config.dart`: database URL (override with `--dart-define=FIREBASE_DB_URL=…`).
- **Profile tab** (`screens/profile/profile_screen.dart`, replaces the “Coming Soon” placeholder): shows the user’s real stored values — name, email, age, gender, height, weight, BMI, goals, conditions, allergies, medications — plus BMR, calorie/macro targets and workout days; pull-to-refresh reloads from the database; Log Out button.
- `ApiClient` + the Express backend are now used **only for label OCR** (`/api/scan/ocr`, which holds the Google Vision key). The old `/api/profile` and `/api/food` Express/Mongo routes are still in `Baymax-main` but unused by the app (the static web prototype still uses the profile routes).

**Verification**
- Rules syntax validated and deployed; anonymous access denied (checked with curl).
- 52 automated tests pass, including new round-trip tests that mimic the database’s behaviour (empty lists are dropped, loosely-typed maps) to make sure a profile and a food entry load back correctly.
- **Not verified:** a real signed-in read/write against the live database (needs a device run with a real account). If the app shows “The database refused access”, the rules did not accept a write — paste the error and we will adjust `database.rules.json`.

**Impact.** Profiles previously saved in MongoDB are not migrated; those users will go through profiling once more.

### 2026-10-09 — Development phase: Modules 1, 2, 3, 7, 8, 12 implemented (model training deferred to phase 2)

**Scope split.** Everything that is plain software engineering was built now. Anything that needs a *trained model* is isolated behind a small interface with a working rule-based/“unavailable” default, so phase 2 only has to drop in the model:

| Phase 2 item | Seam (file) | Today |
|---|---|---|
| Logistic Regression health classifier (M2 FE-3) | `HealthClassifier` in `services/health_classifier.dart`, set via `UserSession.classifier` | WHO BMI rules + medical-condition rules |
| Gradient Boosting calorie optimiser (M3 FR-4) | `CalorieOptimizer` in `services/plan_generator.dart` | Mifflin-St Jeor × activity ± goal, with safety floor |
| MobileNetV2 food-image classifier (M7 FE-8..11) | `FoodImageClassifier` in `services/food_image_classifier.dart` | Photo capture works; user picks the food manually |
| Dialogflow NLU (M12 FR-1) — optional | `ChatbotEngine._detectIntent` | Keyword/phrase scoring with typo tolerance |

**Module 1 (profiling)**
- Step 1 now collects **date of birth** (needed for BMR/classification) and validates input; fixed a bug where the `ft`/`lbs` toggles were ignored in BMI.
- `utils/health_calc.dart`: unit conversion, BMI + WHO bands, **Mifflin-St Jeor BMR**, activity multipliers, calorie targets (−500 / maintain / +300 with a safety floor; no deficit when underweight), macros, water target. The result screen (`bmi_result.dart`) now shows real values instead of the hardcoded 1,485 / 2,050 kcal.
- `HealthProfile` gained derived getters, `fromJson`, `healthClassification`, `planVariant`.

**Module 2 (classification)** — `services/health_classifier.dart`
- Inputs: BMI, age, gender, activity level, medical history. Output: **Healthy / Overweight / Obese / At-Risk / Cardiac / Diabetic** + risk level (Low/Moderate/High), WHO band, risk factors, rationale.
- Precedence: Heart disease → Cardiac; Diabetes → Diabetic; hypertension / asthma / PCOS / underweight / 60+ & sedentary → At-Risk; else by BMI. Saved with the profile (FE-5).
- `health_classification.dart` rewritten (it had white text on pale backgrounds and hardcoded chips).

**Module 3 (plans)** — `services/plan_generator.dart`, `services/exercise_library.dart`, `models/plan.dart`
- **FR-1 medical rules** resolved per user (no high-impact for BMI ≥ 30 / cardiac / hypertension / 55+; no HIIT for cardiac, hypertension, diabetes, asthma; no isometric holds for cardiac/hypertension; session length and weekly-days caps; underweight → strength focus). The reasons are shown to the user on the workout screen.
- **FR-2/3/5** 30-exercise bodyweight library with technique steps; templates by goal (lose / gain / maintain) and frequency; intensity Low/Moderate/High from category and activity level; weekly schedule with rest days; per-day duration and estimated kcal (MET-based).
- **FR-4/6** daily calories, macros (diabetic carbs capped at 40%), water target, and an **allergen-safe meal plan** built from the food database, plus foods to avoid and tips.
- **FE-7 Regenerate**: the plan is a pure function of (profile, variant); only `planVariant` is stored. Consequence: a plan is not a stored document, so doctor edits (Module 13) will need a stored plan later.
- Screens: `workout_plan.dart` (rewritten), `exercise_detail.dart` (parametrised), new `nutrition/nutrition_plan_screen.dart`.

**Module 7 (diet)** — `services/food_database.dart`, `food_parser.dart`, `food_log_service.dart`, screens in `screens/diet/`
- `assets/data/foods.json`: **97 foods** incl. common Pakistani dishes — calories, macros, allergen tags, meal roles. Values are approximate typical-serving figures, not lab data; replace/extend with a verified source (USDA/PFCT) before release.
- Rule-based entity extraction: handles counts, number words, fractions, units (g, cup, bowl…), sizes, plurals, aliases (“2 rotis and a bowl of daal”), fuzzy names.
- Diet tab: week strip, calories vs target, macro bars, per-meal entries with delete; “Log Food” → Type Food / Scan Food / Scan for Allergens. Logged items warn when they contain one of the user’s allergens.
- Backend: `models/FoodEntry.js`, `routes/food.js` (`GET ?date=`, `POST`, `DELETE /:id`, all per-user).

**Module 8 (allergen scanner)** — `services/allergen_matcher.dart`, `ocr_service.dart`, screens in `screens/allergy/`
- Matching: synonym dictionaries (incl. South-Asian terms: maida, atta, ghee, dahi…), **exclusion phrases** (coconut milk, peanut butter, rice flour, nutmeg, eggplant are not flagged for the wrong allergen), OCR digit/letter repair (`mi1k`), **fuzzy matching** flagged as “possible match”, and a separate **“may contain / traces”** tier.
- Result screen: red banner + modal alert + haptic when an allergen is found (FR-5); per-ingredient ✓/⚠; paste-ingredients fallback; shows the raw OCR text.
- Backend `routes/scan.js`: `POST /api/scan/ocr` proxies **Google Vision** (`DOCUMENT_TEXT_DETECTION`); the key stays server-side. `server.js` JSON limit raised to 12 MB for label photos.

**Module 12 (chatbot)** — `services/chatbot_engine.dart`, `screens/chatbot/chatbot_screen.dart`
- Intents: greeting/thanks/bye, BMI, BMR, calorie target, calories remaining today, today’s workout, weekly plan, how-to for any library exercise, calories in any food/meal sentence, meal suggestion (allergen-safe), “can I eat X?”, allergy list, 16 FAQs.
- **FR-4 doctor recommendation:** symptoms → advice to see a doctor; emergency symptoms (chest pain, fainting, breathlessness…) → urgent message; risky topics (fasting, supplements, insulin, HIIT…) for Cardiac/Diabetic/High-risk users → “ask your doctor first”. The “Book a Consultation” chip shows a coming-soon message until Module 13 exists.
- Chat FAB/tile now open this chatbot; the mic icon opens the existing voice assistant (Module 5).

**Wiring / infra**
- `UserSession` (profile → classification → plan cache), `ApiClient` (shared authenticated HTTP; `ProfileService` now uses it), `FoodLogService`, dashboard shows real greeting/calories/target/today’s workout, Diet tab is live, iOS camera/photo permission strings added, `image_picker` added.

**Tests: 48 automated, all passing** (`test/logic_test.dart` 40, `test/screens_test.dart` 7, `test/widget_test.dart` 1). They cover the calculations, every classification path, medical-restriction guarantees (e.g. a cardiac plan never contains high-impact/HIIT/isometric moves; meal plans never contain the user’s allergens across 6 variants), the food parser, allergen edge cases, chatbot intents, and render the new screens at phone size (this caught and fixed several overflow-prone rows).

**Not verified / needs a human**
- Nothing was run on a device or emulator; the backend’s authenticated paths (valid token → Mongo) were not exercised, only that unauthenticated calls get 401.
- **OCR needs `GOOGLE_VISION_API_KEY`** in `Baymax-main/.env` (Google Cloud → enable Vision API → create an API key, restrict it to the Vision API). Until then the scanner returns “not configured” and the paste-ingredients box still works.
- Food calorie values and exercise MET values are reasonable estimates; have them reviewed (e.g. by a nutritionist/trainer on the team) before presenting as medical-grade.

### 2026-10-09 — Auth follow-ups: sessions, Forgot Password, Google, per-user profiles (Module 1)

Closed the "not done" list from the Firebase hookup below.

**App (Flutter)**
- **Session on launch** — `splash_screen.dart` checks for a saved Firebase session; signed-in users skip onboarding/login. New `lib/services/auth_flow.dart` (`AuthFlow.continueAfterAuth`) sends them to the dashboard if a profile exists on the server, otherwise to the profiling wizard. If the server is unreachable it falls back to profiling (with a message) so new users are never skipped; a 401 signs the user out and returns to login.
- **Forgot Password** — dialog on the login screen → `AuthService.sendPasswordReset`. Always shows a neutral "if an account exists…" message.
- **Continue with Google** — `AuthService.signInWithGoogle` via Firebase's provider flow (`signInWithProvider`; popup on web). No extra package and no SHA-1 needed; the **Google provider must be enabled in the Firebase console**. A cancelled sign-in is silent.
- **Log out** — button on the dashboard app bar (previously only existed on profiling step 1, unreachable once logged in).
- **Profile tied to the Firebase user** — new `lib/services/profile_service.dart` calls `PUT/GET /api/profile/me` with the Firebase ID token. `step3_fitness_goals`, `bmi_result`, `health_classification` now use it. A failed save now shows a message instead of failing silently.
- **API base URL** — new `lib/config/api_config.dart`: `10.0.2.2:3000` on the Android emulator, `localhost:3000` elsewhere; override with `--dart-define=API_BASE_URL=http://<lan-ip>:3000` for a physical phone. Replaces three hardcoded `localhost` URLs.
- **Android manifests** — added the missing `INTERNET` permission to the **main** manifest (only debug had it, so release builds had no network); debug manifest allows cleartext http for the local backend.
- `test/widget_test.dart` replaced (it referenced the nonexistent `MyApp`) with a `HealthProfile.toJson` unit test.

**Backend (`Baymax-main`)**
- `npm i firebase-admin`; new `middleware/firebaseAuth.js` verifies the Bearer ID token (project ID only, no service account needed; override with `FIREBASE_PROJECT_ID`).
- `models/UserProfile.js`: new `uid` field (unique, sparse).
- `routes/healthProfile.js`: new `PUT /me` (upsert by uid, whitelisted fields only) and `GET /me`. The old unauthenticated `POST /` and `GET /:id` are **left in place for the static web prototype** (`public/…`); note that `GET /:id` exposes any profile by id with no auth — remove it once the web prototype is retired.

**Verified**
- `flutter analyze`: no errors; `flutter test`: passes; Android debug build compiles.
- Backend: `/me` returns 401 for a missing and for a garbage token (tested with a throwaway script, not touching the database).
- **Not verified:** the full path with a real signed-in user (valid token → Mongo write/read), Google sign-in, and password-reset email — these need a device/emulator run with the console settings below.

**Still open / needs a human**
- Firebase console: enable **Email/Password** and **Google** providers (Authentication → Sign-in method).
- Bundle/application ID is still `com.example.app`. Changing it means registering new Android/iOS apps in Firebase and re-running `flutterfire configure`, so do it once, early, with the final name.
- Web is not configured in `firebase_options.dart` (re-run `flutterfire configure`, select web).
- iOS can't be built on this Mac until Xcode is fully installed and CocoaPods is added.
- Encryption at rest (FE-9) is still not done — profile data is stored in plain form in Mongo.

### 2026-10-09 — Connected Firebase Auth (project `baymax-148da`) — Module 1 FE-1 / FE-2

Reconnected Firebase after the cleanup below, using freshly generated config from `flutterfire configure` (platforms: **android, ios** — web/macOS/windows/linux not configured).

**Tooling fixes along the way**
- `firebase: bad CPU type in executable` — `/usr/local/bin/firebase` was an Intel-only binary on an Apple Silicon Mac without Rosetta. Fixed by `brew install firebase-cli` (native arm64).
- `flutterfire` not on PATH — added `$HOME/.pub-cache/bin` to PATH.
- `flutterfire configure` failed on missing Ruby `xcodeproj` gem — fixed with `gem install --user-install xcodeproj`.

**Generated by flutterfire:** `lib/firebase_options.dart`, `firebase.json`, `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist` (added to the Xcode project). Android gradle `google-services` plugin was already wired.

**Code changes**
- `pubspec.yaml`: added `firebase_core ^4.15.0`, `firebase_auth ^6.7.0`.
- `lib/main.dart`: `WidgetsFlutterBinding.ensureInitialized()` + `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` before `runApp`.
- `lib/services/auth_service.dart`: real implementation — `signIn`, `signUp` (also sets display name), `signOut`, `currentUser`. Firebase error codes are mapped to readable messages and re-thrown as `AuthException`, so login/signup/logout screens needed no further changes.
- `ios/Runner.xcodeproj/project.pbxproj`: iOS deployment target 13.0 → **15.0** (required by the new Firebase plugins).

**Not done / still needed**
- Firebase console: **Authentication → Sign-in method → Email/Password must be enabled**, otherwise signup returns "Email/password sign-in is not enabled".
- Web is not configured (re-run `flutterfire configure` and select web to run in Chrome).
- "Forgot Password?" and "Continue with Google" buttons are still placeholders.
- Bundle/application ID is still the template `com.example.app` — rename before any release.
- Login does not yet check for an existing session on launch (splash always shows onboarding), and the user's profile is not yet linked to their Firebase UID (needed for FE-9).

### 2026-10-09 — Removed old Firebase integration

The old Firebase project (`baymax-148da`) was removed so a new one can be connected. The app still compiles; auth calls now go through a stub that reports "backend not connected".

**Removed**
- `firebase_core` and `firebase_auth` from `pubspec.yaml`.
- `Firebase.initializeApp(...)` and the hardcoded `FirebaseOptions` block (API key, app ID, project ID, auth domain, storage bucket, measurement ID) from `lib/main.dart`.
- All `FirebaseAuth` / `FirebaseAuthException` usage from `login_screen.dart`, `signup_screen.dart`, `step1_personal_info.dart`.
- Stale generated plugin registrations for firebase (`windows/`, `macos/`, `ios/` `GeneratedPluginRegistrant` / `generated_plugins.cmake`, `.flutter-plugins-dependencies`) — regenerated by `flutter pub get`, no Firebase references remain.
- `pubspec.lock` re-resolved; dropped `firebase_*`, `_flutterfire_internals`, `flutter_web_plugins`.

**Added**
- `lib/services/auth_service.dart` — `AuthService.instance` with `signIn`, `signUp`, `signOut` and an `AuthException`. All three are stubs (`signIn`/`signUp` throw `AuthException('Authentication backend is not connected yet.')`). This is the single place to plug in the new Firebase project (or the JWT API).

**Changed**
- `login_screen.dart`, `signup_screen.dart`, `step1_personal_info.dart` now call `AuthService.instance.*` and catch `AuthException`.

**Verification**
- `flutter pub get` succeeds; `flutter analyze` reports **no errors in `lib/`**. Remaining output is pre-existing lint (`withOpacity`, `MaterialState` deprecations, etc.).
- One pre-existing analyzer error remains and is unrelated to this change: `test/widget_test.dart:16` references `MyApp`, which doesn't exist (the app class is `BaymaxApp`). Default Flutter template test, never updated.
- Not done: no Android/iOS native Firebase files existed (`google-services.json`, `GoogleService-Info.plist`, `firebase_options.dart` were never in the repo), so nothing to delete there. The app has not been run on a device/emulator after the change.

**Follow-ups for whoever connects the new Firebase**
- Run `flutterfire configure` (generates `firebase_options.dart`, `google-services.json`, `GoogleService-Info.plist`), add `firebase_core`/`firebase_auth` back, initialise in `main.dart`, and implement the three `AuthService` methods.
- The old project's web API key was committed in source. Restricting/deleting that key in the Firebase console is worthwhile if the project is still live. This folder is not a git repo, so there is no history to scrub — but keep new keys/config out of any repo you create later (`.gitignore` the generated files if the repo will be public).
- `../Baymax-main/.env` holds the Mongo connection string; keep it out of version control.

### 2026-10-09 — Baseline audit & this document created

Initial review of the existing codebase against the scope doc (results in section 3).

---

## 3. Module status detail

Status as of 2026-10-09 (end of the development-phase push). `[x]` implemented and covered by an automated test or a successful build, `[~]` implemented but needs an external setup or a device test, `[ ]` not done (phase 2 unless noted).

### Module 1 — User Authentication & Health Profiling

- [~] FE-1 Register (Firebase Auth email/password; backend verifies the Firebase ID token — a signed JWT). Needs Email/Password enabled in the console + device test. Password-strength bar is still a static mock.
- [~] FE-2 Login / logout / forgot password / Google / saved session. Needs Google provider enabled + device test.
- [x] FE-3 Personal info incl. **date of birth**, gender, height (cm/ft), weight (kg/lbs), with validation.
- [x] FE-4 Medical history and allergies (step 2).
- [x] FE-5 Fitness goal, activity level, target weight, frequency (step 3).
- [x] FE-6 BMI (unit-correct, WHO band) — tested.
- [x] FE-7 BMR, Mifflin-St Jeor — tested.
- [x] FE-8 Daily calories (deficit / maintain / surplus, safety floor) — tested.
- [~] FE-9 Stored per user in the Firebase Realtime Database, protected by per-user security rules. **At-rest/field encryption not done** (belongs with Module 14 FR-1, AES).

### Module 2 — AI Health Classification Engine

- [x] FE-1 Inputs: BMI, age, gender, activity level (+ conditions).
- [x] FE-2 WHO BMI rules.
- [x] FE-3 Logistic Regression model — trained on CDC survey data and integrated as a hybrid with the rules (AUC 0.73–0.76; see 2026-10-09 Phase 2 entry for limits).
- [x] FE-4 Healthy / Overweight / Obese / At-Risk / Cardiac / Diabetic (+ risk level, factors, rationale).
- [x] FE-5 Result stored on the profile (`healthClassification`).

### Module 3 — Intelligent Personalized Plan Generator

- [x] FR-1 Medical restriction rules (shown to the user).
- [x] FR-2 Workout template selection (32 exercises loaded from Firestore, each with Compendium code and technique/muscle provenance; goal-based templates).
- [x] FR-3 Intensity by health category and activity level.
- [~] FR-4 Calorie target — rule-based now; **Gradient Boosting optimisation is phase 2** (`CalorieOptimizer` seam ready).
- [x] FR-5 Weekly schedule with rest days, duration and kcal per day.
- [x] FR-6 Calorie + macro breakdown, allergen-safe meal plan.
- [x] FE-7 Regenerate plan.

### Module 7 — Smart Diet & Calorie Tracking

- [x] FE-1/2 Choose text entry or image scan (Log Food sheet).
- [x] FR-3 Text entry.
- [x] FR-4 Food entity extraction (rule-based parser, not a trained NLP model).
- [~] FE-5 Calorie data fetched from a **Cloud Firestore catalogue** (97 foods, offline-cached, bundled fallback). Values are still estimates until verified against USDA (needs the API key).
- [x] FE-6 Total calories.
- [~] FE-7 Capture / upload food image (works; needs a device test).
- [ ] FE-8..FE-11 MobileNetV2 classification, DB match, calorie estimate — **phase 2** (`FoodImageClassifier` seam ready; manual pick in the meantime).
- [x] FE-12 Daily intake updated automatically (per-user food log, dashboard + Diet tab).

### Module 8 — Allergy & Ingredient Scanner

- [~] FR-1 Scan product label (camera/gallery; needs a device test).
- [~] FR-2 OCR via Google Vision API (backend proxy done; **needs `GOOGLE_VISION_API_KEY`**).
- [x] FR-3 Compare with the user’s allergy list.
- [x] FR-4 Fuzzy matching.
- [~] FR-5 High-priority alert: in-app modal + banner + haptic. Push notification via FCM belongs to Module 14.

### Module 12 — AI Chatbot

- [x] FR-1 Intent detection (rule-based; Dialogflow can replace it later).
- [x] FR-2 FAQs.
- [x] FR-3 Calorie / workout information, personalised.
- [x] FR-4 Recommends doctor consultation (booking itself is Module 13).

---

## 4. Cross-cutting issues

1. **Stack mismatch (resolved for now).** Scope says JWT + MongoDB; we use Firebase Auth for login and Express/MongoDB for data, with the backend verifying Firebase ID tokens. Confirm with the supervisor that this is acceptable.
2. **Legacy open route (Express/Mongo, no longer used by the app).** `GET /api/profile/:id` and `POST /api/profile` are unauthenticated (kept for the static web prototype in `Baymax-main/public`). Remove them when the prototype is retired — `GET /:id` exposes any profile by id.
3. ~~Hardcoded `localhost:3000`~~ — fixed (`lib/config/api_config.dart`). Production URL/HTTPS still to be decided.
4. ~~Mocked BMR/calories/plan/classification~~ — replaced with real logic.
5. **Data quality.** Food calories and exercise METs are estimates. A verified food-composition source and a professional review are advisable before any claim of accuracy.
6. **No at-rest encryption** of health data yet (Module 14).
7. **Third-party keys needed:** Google Vision (Module 8) and a free USDA FoodData Central key (`USDA_API_KEY`) to verify the food table. Dialogflow only if we choose it for Module 12/5.
8. **Plans are derived, not stored** (see Module 3 note) — revisit when doctors can edit plans (Module 13).
9. **Bundle ID** is still `com.example.app`; **web** is not configured for Firebase; **iOS** cannot be built on the dev Mac until Xcode/CocoaPods are installed.

---

## 5. Phase 2 backlog (model training)

1. **Module 2** — Logistic Regression health classifier (scikit-learn): dataset, training, evaluation; serve via a small Python service or export to the app; implement `HealthClassifier`.
2. **Module 3** — Gradient Boosting calorie-target optimiser; implement `CalorieOptimizer`.
3. **Module 7** — MobileNetV2 food classifier (TensorFlow Lite) + food-image dataset; implement `FoodImageClassifier`, then map classes to the calorie database and estimate portions.
4. Optional: Dialogflow for Module 12 (and Module 5).
5. Shared: field-level encryption (Module 14), verified food database, bundle ID + release config.

---

## 6. Weekly log

Add an entry each week: what was done, what's blocked, what's next.

| Week of | Done | Blocked | Next |
|---------|------|---------|------|
| 2026-10-09 | Firebase removed; baseline audit; this doc | New Firebase project credentials | Connect auth; real BMI/BMR/calorie calc |
| 2026-10-09 (cont.) | Modules 1, 2, 3, 7, 8, 12 implemented; 48 tests passing; Android build compiles | Google Vision key; device testing | Device test pass; supervisor check on auth stack; start phase 2 data collection |
