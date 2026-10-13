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
| 12 | AI Chatbot | Aamna | S-30 (+ S-31 for doctor referral) | 🟡 Rule-based bot built & tested; Dialogflow optional later |
| 11 | Community Ranking & Gamification | (not in the focus list) | — | 🟡 Score, badges, levels, opt-in leaderboard built & tested (FR-1,2,3,5); K-Means only with 15+ users; scores not tamper-proof; not run on a device |
| 14 | Secure Data Management & Smart Alerts | (not in the focus list) | — | 🟡 Roles, workout reminders, inactivity alerts done (FR-2,3,5); **AES, injury alerts, FCM push not done** |

Legend: 🔴 not started · 🟡 in progress / partial · 🟢 done & verified

> **Open question:** the brief says "9 modules for now" but names six (1, 2, 3, 7, 8, 12). The other three are not yet identified here — add them to the table above once confirmed.

---

## 2. Change log

Newest first. Format: date · what changed · files · why.

### 2026-10-13 — Module 3 FR-4: adaptive calorie-target optimiser (algorithm; NOT Gradient Boosting)

- **Why not Gradient Boosting:** it needs measured daily energy expenditure. The only suitable source, the IAEA doubly-labelled-water database (dlwdatabase.org), is free but released on request (an application form reviewed by its management group), so it cannot be downloaded today. No model was trained on made-up or unsuitable data (rule 2). The scope wording "optimize calorie targets using Gradient Boosting" is therefore **not met literally**; discuss with the supervisor (reword FR-4, or apply to the IAEA).
- **What was built** (`services/calorie_optimizer.dart`, pure Dart): from the user's own weigh-ins and food logs (last 28 days) it estimates maintenance calories by energy balance: mean logged intake − (least-squares weight slope × 7,700 kcal/kg). That is combined with the Mifflin–St Jeor × activity estimate by a normal–normal Bayesian update (prior sd 10% of the formula, observation sd from the slope's standard error plus 10% logging error), so noisy weights count for less. It plugs into the existing `CalorieOptimizer` seam (`AdaptiveCalorieOptimizer`); the target is rebuilt with the same minimum-intake floors (1,200 F / 1,500 M, at least BMR on a deficit) and the underweight no-deficit rule.
- **Safeguards:** needs >= 4 weigh-ins over >= 14 days and >= 10 "fully logged" days (a day with under 60% of BMR logged is ignored); data share capped at 70%; may raise the formula by <= 15% and lower it by <= 10%; changes under 100 kcal ignored; **if the logs imply a need more than 30% from the formula the data is rejected** (almost always unlogged meals); **off for under-18s and for reported heart disease or diabetes** (formula target kept). Found by simulation: someone logging only 60% of their food would otherwise have been given a lower target (1,898 -> 1,744 kcal); the plausibility guard and the tighter decrease limit were added because of it.
- **App:** new weight log (`services/weight_service.dart`, `users/{uid}/weights/{date}`); `UserSession` keeps `calorieEstimate`, rebuilds the plan (target, macros, meals) when it changes, refreshes in the background after sign-in, and `logWeight()` also keeps the profile weight current. New screen "Your calorie target" (Nutrition Plan -> "How is my target worked out?", and Profile): target, how it was worked out in plain words, a checklist of what data is still needed, weight check-in and a weight/trend chart. Sources screen entry added with the equation sources (Mifflin 1990; Wishnofsky 1958; Hall 2011) and the honest list of team-chosen assumptions.
- **Tests:** 143 pass (new: 19 in `calorie_optimizer_test.dart` using simulated people with measurement noise, 7 in `calorie_target_screen_test.dart` including that the plan's target, macros and meals follow the estimate and that a diabetic user keeps the formula). `flutter build apk --debug` succeeds.
- **Database rules:** `weights` node added to `database.rules.json` (kg 20-400, one entry per date). Deploy approved by the user and attempted on 2026-10-13, but it **failed: this Mac could not resolve Firebase host names** (`curl: (6) Could not resolve host`; nslookup worked, so a local resolver problem), nothing was changed in the cloud. **Still to do:** `firebase deploy --only database --project baymax-148da`, then check anonymous access to `users/x/weights` is denied. Until then, saving a weight shows "The database refused access".
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
