# Baymax — Phase 2: model training

Three models, one per module. Allergy scanning (Module 8) needs no training and is not part of this folder.

| Module | Model | Dataset | Trained here? | Ships as |
|---|---|---|---|---|
| 2 | Logistic Regression health-risk classifier | CDC Diabetes Health Indicators (UCI 891) | **Yes** | `assets/models/health_classifier.json` + `.tflite` |
| 3 | Gradient Boosting workout-calorie model | Gym Members Exercise Dataset (Kaggle) | **No** — dataset needs a Kaggle login | `assets/models/calorie_gb.json` |
| 7 | MobileNetV2 food recognizer | Food-101 + Indian/South-Asian food sets + your own photos | **No** — needs a GPU and ~5 GB of images | `assets/models/food_classifier.tflite` + `food_classifier_labels.json` |

The app already contains the code that uses all three. **Each model switches on by itself when its file is in `assets/models/`**; without the file the app keeps using the rule-based version. No code changes are needed.

---

## 1. Dataset links

| Dataset | Link | License | Size | Checked |
|---|---|---|---|---|
| **CDC Diabetes Health Indicators** (Module 2) | https://archive.ics.uci.edu/dataset/891/cdc+diabetes+health+indicators — direct CSV: https://archive.ics.uci.edu/static/public/891/data.csv | see the UCI page | 13.5 MB, 253,680 rows | Downloaded and used. The survey year is inconsistent: UCI's summary links the **2014** BRFSS page, the Kaggle copy says **2015**. Original source: https://www.cdc.gov/brfss/annual_data/annual_2014.html |
| **Gym Members Exercise Dataset** (Module 3) | https://www.kaggle.com/datasets/valakhorasani/gym-members-exercise-dataset | check the Kaggle page | 973 rows | Link taken from search listings; Kaggle blocks automated access so I could not open it. Provenance is unclear (such datasets are often synthetic) — treat as a prototype. |
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

## 4. Module 3 — Gradient Boosting (script ready, needs the Kaggle dataset)

**What it does:** predicts calories burned in one workout from age, sex, weight, height, session length, experience and workout type — inputs the app already has (no heart-rate data). It is compared with the Compendium MET estimate the app uses today, and **exported only if it is more accurate on held-out data**.

Kaggle:
1. Create a notebook, **Add data → Gym Members Exercise Dataset**.
2. Upload `ml/calorie_model/train.py`, then run:
   ```
   !python train.py --csv /kaggle/input/gym-members-exercise-dataset/gym_members_exercise_tracking.csv --out /kaggle/working
   ```
3. If it prints `wrote .../calorie_gb.json`, download it into `assets/models/`. If it says it was **not exported**, the model did not beat the MET baseline — keep the app as is.

Local: download the CSV from Kaggle, then `ml/.venv/bin/python ml/calorie_model/train.py --csv <file>`.

Gradient-boosted trees have no TFLite operator, so the trees are exported as arrays and evaluated by `GradientBoostingModel` in Dart (checked against scikit-learn in `test/ml_models_test.dart`).

**Honest scope note:** the scope document asks for Gradient Boosting to *optimise daily calorie targets*. That needs measured daily energy expenditure (IAEA data above). This model improves the **per-workout** calorie estimate instead. It does not change the daily calorie target.

---

## 5. Module 7 — MobileNetV2 food recognizer (script ready, train on Kaggle)

**What it does:** transfer-learns MobileNetV2 on photos of foods that exist in the app's food catalogue, then exports a float16 TFLite model (about 5 MB). It predicts only the **dish**, not the portion; the user confirms and adjusts the portion on the next screen. Predictions below 35% confidence are not offered.

**Classes:** only dataset classes mapped to catalogue foods in `ml/food_classifier/class_map.py` are used, so every prediction has calories behind it. Food-101 contributes about 12 catalogue foods (chicken curry, samosa, pizza, fries, ice cream, omelette, hummus, burger, sandwich, grilled fish, pasta, salad, cake). **Pakistani dishes only appear if you add photos** (`--custom`) or an Indian set (`--extra`) that has them. The training log lists unmapped folders and foods the catalogue lacks.

Kaggle (GPU T4 ×2, roughly 1–3 hours):
1. New notebook → **Add data** → Food-101 (`kmader/food41`) and any extra sets or your own photo folders; enable **GPU**.
2. Upload `train_kaggle.py` and `class_map.py` to the notebook, then:
   ```
   !python train_kaggle.py --food101 /kaggle/input/food41 \
        --extra /kaggle/input/<indian-food-set> \
        --custom /kaggle/input/<your-photos-named-by-catalogue-id> \
        --out /kaggle/working
   ```
3. Download `food_classifier.tflite` and `food_classifier_labels.json` into `assets/models/`, rebuild the app.

`--custom` folders must be named with catalogue ids, e.g. `custom/chicken_biryani/IMG_001.jpg`.

**Check the pipeline locally in about a minute** (synthetic images, produces no useful model — it only proves training → export → inference works):
```bash
ml/.venv/bin/python ml/food_classifier/smoke_test.py
```

The script also checks that the exported TFLite model gives the same answers as the trained model (it stops if they agree on fewer than 95% of validation images). Read `food_classifier_labels.json` after training: it holds top-1/top-3 accuracy and the per-class accuracy. Do not ship a class that scores poorly.

---

## 6. Using the models in the app

Copy the files into `assets/models/` and rebuild. The app loads each one if present:

| File | Used by |
|---|---|
| `health_classifier.json` | `UserSession` → `HybridHealthClassifier` (classification screen) |
| `calorie_gb.json` | `UserSession` → `PlanGenerator` (workout calories show "Calories (AI)") |
| `food_classifier.tflite` + `food_classifier_labels.json` | `TfliteFoodClassifier` (Diet → Log Food → Scan Food) |

To change the catalogue (add dishes so the model can recognise them): edit `assets/data/foods.json`, run `node Baymax-main/tools/seed_firestore.js <file> --collection foods`, add the new class to `class_map.py` and retrain.
