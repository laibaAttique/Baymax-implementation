# Baymax — Phase 2: model training

Three models, one per module. Allergy scanning (Module 8) needs no training and is not part of this folder.

| Module | Model | Dataset | Trained here? | Ships as |
|---|---|---|---|---|
| 2 | Logistic Regression health-risk classifier | CDC Diabetes Health Indicators (UCI 891) | **Yes** | `assets/models/health_classifier.json` + `.tflite` |
| 3 | Gradient Boosting workout-calorie model | Gym Members Exercise Dataset (Kaggle) | Cleaned and tested here — **blocked: the data is not physiologically realistic** (see section 4) | `assets/models/calorie_gb.json` (not produced) |
| 7 | MobileNetV2 food recognizer | Food-101 (downloaded, cleaned) + your own Pakistani photos | Dataset cleaned and packaged; **train on Kaggle (GPU)** | `assets/models/food_classifier.tflite` + `food_classifier_labels.json` |

The app already contains the code that uses all three. **Each model switches on by itself when its file is in `assets/models/`**; without the file the app keeps using the rule-based version. No code changes are needed.

---

## 1. Dataset links

| Dataset | Link | License | Size | Checked |
|---|---|---|---|---|
| **CDC Diabetes Health Indicators** (Module 2) | https://archive.ics.uci.edu/dataset/891/cdc+diabetes+health+indicators — direct CSV: https://archive.ics.uci.edu/static/public/891/data.csv | see the UCI page | 13.5 MB, 253,680 rows | Downloaded and used. The survey year is inconsistent: UCI's summary links the **2014** BRFSS page, the Kaggle copy says **2015**. Original source: https://www.cdc.gov/brfss/annual_data/annual_2014.html |
| **Gym Members Exercise Dataset** (Module 3) | https://www.kaggle.com/datasets/valakhorasani/gym-members-exercise-dataset | check the Kaggle page | 973 rows | Downloaded and analysed. Tidy but **synthetic-looking**: yoga burns as much per kg-hour as HIIT. See section 4. |
| **Food-101** (Module 7) | Official: https://data.vision.ee.ethz.ch/cvl/datasets_extra/food-101/ — archive: http://data.vision.ee.ethz.ch/cvl/food-101.tar.gz — Kaggle copy: https://www.kaggle.com/datasets/kmader/food41 | research use (see official page) | 4.65 GB, 101 classes × 1,000 images | Official page and archive respond. Kaggle copy name from search listings. |
| **Khana** — 131K images, 80 Indian dishes (Module 7) | Paper: https://arxiv.org/abs/2509.06006 — site: https://khana.omkar.xyz | **CC BY-NC-ND 4.0** (non-commercial, no derivatives) | ~131K images | Paper page checked. Check whether a model trained on it counts as a derivative before any commercial use. |
| **Indian food images** on Hugging Face | https://huggingface.co/datasets/rajistics/indian_food_images | not stated | ~6K images, 20 classes | Metadata checked via the HF API. |
| **Pakistani food** (object detection, Roboflow) | https://universe.roboflow.com/calgenie/pakistani_food | CC BY 4.0 | small | Listed in search results; the site refused automated access. Detection format, not per-dish folders — export as classification or crop the boxes. |
| Your own photos of Pakistani dishes | — | yours | — | **Recommended.** No Kaggle/UCI dataset of Pakistani dishes was found. 50–100 phone photos per dish (biryani, karahi, nihari, haleem, daal, roti…) will help far more than another foreign dataset. |
| **IAEA doubly-labelled-water database** (measured daily energy expenditure) | https://doubly-labelled-water-database.iaea.org/home | by application | 6,000+ measurements | **Not downloadable** — access is by request. This is the right data for the scope's "optimise calorie targets"; the team should apply (ask your supervisor). |
| 2024 Compendium of Physical Activities | https://pacompendium.com | — | — | Already used for exercise energy values. |

---

## 2. Environment

```bash
cd "<project>/app"
python3 -m venv ml/.venv
ml/.venv/bin/pip install numpy pandas scikit-learn joblib pillow tensorflow
```
`ml/.venv/` and `ml/data/` are git-ignored. On Kaggle nothing needs installing.

---

## 3. Module 2 — Logistic Regression (done)

```bash
curl -o ml/data/cdc_diabetes_health_indicators.csv https://archive.ics.uci.edu/static/public/891/data.csv
ml/.venv/bin/python ml/health_classifier/train.py          # writes assets/models/health_classifier.{json,tflite}
```

**Inputs:** BMI, age, sex, active (yes/no). **Output:** probabilities for Healthy / Overweight / Obese / At-Risk / Cardiac / Diabetic.

**Results on 20% held-out data (50,620 adults):**
- 6-class accuracy **40%**, macro-F1 **0.40** — weak, and expected: four demographic inputs cannot tell apart the "At-Risk" group (high blood pressure/cholesterol).
- Risk ranking is useful: **ROC-AUC 0.76 (heart disease), 0.73 (diabetes)**.
- Flag thresholds are chosen so only the highest-risk ~15% of people are flagged, with about 2.5× the base rate of true cases (diabetes: 27% of flagged people have it vs 11% overall; heart disease: 25% vs 9%).

**How the app uses it** (`HybridHealthClassifier`): the rule engine decides first (reported conditions and WHO BMI bands always win). The model adds a risk estimate to the classification screen, and only if *nothing* was reported and the risk is in the top ~15% does it change the category to At-Risk. It never assigns Cardiac or Diabetic itself.

**Limits:** US survey data, self-reported; not validated for South Asians (who develop diabetes at lower BMI); screening estimate, not a diagnosis. The app says so on screen and in Profile → Sources & methodology.

**TFLite vs JSON:** the app evaluates the model from the JSON weights in plain Dart (about 40 multiplications, exactly unit-tested against scikit-learn's outputs). `health_classifier.tflite` (2.6 KB) is exported and verified against scikit-learn (max difference 1.4e-6) if you prefer to run it through the TFLite interpreter.

---

## 4. Module 3 — Gradient Boosting (cleaned and tested; do not ship a model from this dataset)

Files: `ml/calorie_model/train_kaggle_notebook.ipynb` (**one-file Kaggle notebook: clean → analyse → train → safety check → report; upload this**), `ml/calorie_model/clean_data.py` (cleaning), `ml/calorie_model/train.py` (the same training as a script, with the safety gate). A ready-to-upload Kaggle package (`gym_dataset_kaggle.zip`) contains the cleaned CSV, the cleaning report and both scripts.

**Cleaning:** 973 → 950 rows. The file is already tidy (no missing values, no duplicates, consistent text and BMI); the only impossible rows were 23 sessions whose *average* heart rate exceeded the *maximum*. Nothing is imputed.

**What the analysis found (this matters more than the cleaning):**
- Calories per kg-hour (the MET a session implies) is ≈10 for **every** workout type; workout type explains 0.4% of the variation (ANOVA F ≈ 1). Published values differ ~3× between yoga (2.3) and HIIT (7.5) (2024 Compendium).
- 0 of 232 yoga sessions and 23 of 254 strength sessions have an energy cost within 0.5×–2× of the Compendium; overall only 48% do.
- Experience level and weekly frequency follow a perfect generated pattern (level 1 → 2–3 days, level 2 → 3–4, level 3 → 4–5).
- A Gradient Boosting model trained on it predicts ≈765 kcal for one hour of *any* workout type (yoga 761, HIIT 765) and does not even learn that heavier people burn more. It still "beats" the Compendium estimate on this data (error 86 vs 461 kcal) — because the data, not the Compendium, is wrong.

**Safety gate in `train.py`:** a model is exported only if it (1) beats the MET estimate on held-out data **and** (2) agrees with published energy costs for a standard person within 0.5×–2× for every workout type and increases with body weight. On this dataset check (2) fails, so no `calorie_gb.json` is written and the app keeps using the Compendium. The script always writes `calorie_model_report.json` with the evidence.

**Kaggle:** upload the zip as a **private** dataset (check the original dataset's licence before sharing), add it to a notebook, run
`!python /kaggle/input/<slug>/train.py --csv /kaggle/input/<slug>/gym_members_clean.csv --out /kaggle/working`.
The result will be the same refusal; Kaggle adds nothing here, because no GPU or extra data is involved.

**What to do instead (decisions for the team/supervisor):**
1. Use this dataset only as a documented demonstration of the pipeline, and state in the report that the app uses the peer-reviewed Compendium because the dataset failed validation.
2. Find data with *measured* energy expenditure (indirect calorimetry). The IAEA doubly-labelled-water database is the authentic source for daily energy (by application: https://doubly-labelled-water-database.iaea.org).
3. The scope's "optimise calorie targets using Gradient Boosting" needs daily-expenditure data, not per-session data; item 2 is the route to a legitimate model.

## 5. Module 7 — MobileNetV2 food recognizer (dataset cleaned, ready to train on Kaggle)

Your `foodarchive.zip` is the Kaggle copy of **Food-101** (101 dishes × 1,000 photos, 5.7 GB, with the authors' official train/test split).

**Cleaning** (`ml/food_classifier/clean_images.py`; package: `food_dataset_kaggle.zip`, 452 MB):
- Only the 17 Food-101 dishes that map to catalogue foods were used (the other 84 were left out), merged into **13 catalogue foods** (pasta from 3 dishes, cake from 3).
- Every image was opened and checked (corrupt, too small, extreme shape); exact and near-duplicate photos removed (13 duplicates, 7 training images that were near-copies of validation images, 2 near-identical images across different dishes).
- **Split:** the authors' official *test* images are the validation set (manually cleaned); official *training* images are capped at 600 per class → **7,800 train / 4,249 validation**, longest side 384 px.
- **Known issue:** Food-101's training photos contain some wrongly labelled pictures (e.g. naan among "chicken curry", onion rings among "french fries", pita chips without hummus). Hashing can't find these. Validation is clean, so measured accuracy is trustworthy. After a first run, review training images the model confidently assigns to another class.

**Easiest: use the one-file notebook** `ml/food_classifier/train_kaggle_notebook.ipynb` (copy: `module7_food_model_kaggle.ipynb`). It trains an EfficientNetV2-B0 (stronger than the MobileNetV2 script), runs an automatic label-noise pass, evaluates on a held-out test set that no decision ever sees, exports a float16 TFLite model, verifies it against the trained model, and **only writes `food_classifier.tflite` if it passes a shipping gate** (test top-1 ≥ 85%, every class recall ≥ 70%, TFLite agrees with the trained model on ≥ 98% of images). Otherwise it saves `food_classifier_CANDIDATE.tflite` and says why. The exported model contains only standard TFLite operations (no Flex ops), and the app reads the input size and recommended minimum confidence from `food_classifier_labels.json`. Tested end to end in quick mode (untrained weights) on the real cleaned data: training, noise pass, evaluation, export, parity (100%) and the gate all run.

**Run the script version on Kaggle** (free GPU, roughly 20–40 minutes):
1. Upload `food_dataset_kaggle.zip` as a **private** dataset; new notebook → Add Input → your dataset; Accelerator = GPU T4; Internet = On (to fetch the ImageNet starting weights once).
2. `!python /kaggle/input/<slug>/train_kaggle.py --prepared /kaggle/input/<slug> --out /kaggle/working`
3. Download `food_classifier.tflite` + `food_classifier_labels.json` into `assets/models/`.

The script exports a float16 TFLite model (~4.5 MB) and refuses to finish if the TFLite model disagrees with the trained model on more than 5% of validation images. Read `food_classifier_labels.json` afterwards: it has top-1/top-3 accuracy and per-class accuracy. Do not ship a class that scores poorly.

**Tested here:** the package was unzipped fresh and run exactly as above with no pretrained weights, 1 epoch and 20 images/class: it trained, exported a 4.5 MB TFLite model and the TFLite output matched the trained model on 100% of images. That trial's accuracy (7.7%) is chance level, as expected. Real accuracy needs the Kaggle run.

**Limits:** Food-101 is mostly Western dishes. **No Pakistani dishes** (biryani, karahi, nihari, haleem, daal) are in it. Add your own photos in a folder named with the catalogue id (e.g. `chicken_biryani/`) and pass `--custom <folder>`; without them the app cannot recognise those dishes. The model predicts the dish, not the portion.

**Local pipeline check without any dataset** (synthetic images, about a minute): `ml/.venv/bin/python ml/food_classifier/smoke_test.py`.

---

## 6. Using the models in the app

Copy the files into `assets/models/` and rebuild. The app loads each one if present:

| File | Used by |
|---|---|
| `health_classifier.json` | `UserSession` → `HybridHealthClassifier` (classification screen) |
| `calorie_gb.json` | `UserSession` → `PlanGenerator` (workout calories show "Calories (AI)"). **Not currently produced — see section 4.** |
| `food_classifier.tflite` + `food_classifier_labels.json` | `TfliteFoodClassifier` (Diet → Log Food → Scan Food) |

To change the catalogue (add dishes so the model can recognise them): edit `assets/data/foods.json`, run `node Baymax-main/tools/seed_firestore.js <file> --collection foods`, add the new class to `class_map.py` and retrain.
