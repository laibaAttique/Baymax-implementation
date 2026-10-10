#!/usr/bin/env python3
"""Module 3 — Gradient Boosting workout-energy model.

Predicts calories burned in a workout session from inputs the app already has
(age, sex, weight, height, session length, experience level, workout type) and
compares it with the Compendium-of-Physical-Activities MET estimate the app uses
today. The model is exported only if it beats that baseline on held-out data.

Data (Kaggle — needs a free login; attach it to a Kaggle notebook or download the CSV):
  "Gym Members Exercise Dataset", 973 rows, by valakhorasani
  https://www.kaggle.com/datasets/valakhorasani/gym-members-exercise-dataset
  Columns: Age, Gender, Weight (kg), Height (m), Max_BPM, Avg_BPM, Resting_BPM,
  Session_Duration (hours), Calories_Burned, Workout_Type, Fat_Percentage,
  Water_Intake (liters), Workout_Frequency (days/week), Experience_Level, BMI

HONEST LIMITS
  * Small (973 rows) and of unclear provenance: Kaggle fitness datasets are often
    synthetic. Treat results as a prototype, not validated physiology.
  * Heart-rate columns are NOT used — the app has no heart-rate sensor.
  * The scope document's "optimise calorie targets" ideally uses *measured* daily energy
    expenditure; the only authentic source (IAEA doubly-labelled-water database) is by
    application only: https://doubly-labelled-water-database.iaea.org

Run (Kaggle):  !python train.py --csv /kaggle/input/gym-members-exercise-dataset/gym_members_exercise_tracking.csv --out /kaggle/working
Run (local):   ml/.venv/bin/python ml/calorie_model/train.py --csv path/to/gym_members_exercise_tracking.csv
Output: calorie_gb.json  (copy to assets/models/ in the app)
"""
import argparse
import json
import os
from datetime import datetime, timezone

import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import KFold, cross_val_predict, train_test_split

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

# Fixed METs from the 2024 Adult Compendium of Physical Activities (pacompendium.com):
#   02175 Yoga, general 2.3 | 02054 Resistance training, multiple exercises 3.5
#   02000 Aerobic, general 7.3 | 02040 Circuit training, vigorous 7.5
COMPENDIUM_MET = {'Yoga': 2.3, 'Strength': 3.5, 'Cardio': 7.3, 'HIIT': 7.5}
TYPES = ['Cardio', 'HIIT', 'Strength', 'Yoga']
FEATURES = ['age', 'sex_male', 'weight_kg', 'height_m', 'duration_h', 'experience',
            'is_cardio', 'is_hiit', 'is_strength', 'is_yoga']


def find_csv(path):
    """Accept a CSV file or a folder (e.g. /kaggle/input/gym-members-exercise-dataset)."""
    if os.path.isfile(path):
        return path
    for dirpath, _, files in os.walk(path):
        for f in sorted(files):
            if f.lower().endswith('.csv'):
                return os.path.join(dirpath, f)
    raise SystemExit(f'No CSV found in {path}')


def load(csv_path):
    csv_path = find_csv(csv_path)
    print('reading', csv_path)
    df = pd.read_csv(csv_path)
    df.columns = [c.strip() for c in df.columns]
    need = ['Age', 'Gender', 'Weight (kg)', 'Height (m)', 'Session_Duration (hours)', 'Calories_Burned',
            'Workout_Type', 'Experience_Level']
    missing = [c for c in need if c not in df.columns]
    if missing:
        raise SystemExit(f'CSV is missing columns {missing}. Found: {list(df.columns)}')
    df = df.dropna(subset=need)
    X = pd.DataFrame({
        'age': df['Age'],
        'sex_male': (df['Gender'].str.lower() == 'male').astype(int),
        'weight_kg': df['Weight (kg)'],
        'height_m': df['Height (m)'],
        'duration_h': df['Session_Duration (hours)'],
        'experience': df['Experience_Level'],
        **{f'is_{t.lower()}': (df['Workout_Type'] == t).astype(int) for t in TYPES},
    })[FEATURES]
    y = df['Calories_Burned'].astype(float)
    met = df['Workout_Type'].map(COMPENDIUM_MET).astype(float)
    baseline = met * df['Weight (kg)'] * df['Session_Duration (hours)']  # kcal = MET x kg x h
    return X, y, baseline, df


def report(name, y_true, y_pred):
    mae = mean_absolute_error(y_true, y_pred)
    rmse = mean_squared_error(y_true, y_pred) ** 0.5
    r2 = r2_score(y_true, y_pred)
    print(f'  {name:34s} MAE {mae:7.1f} kcal | RMSE {rmse:7.1f} | R2 {r2:6.3f}')
    return {'mae': float(mae), 'rmse': float(rmse), 'r2': float(r2)}


def tree_to_dict(est):
    t = est.tree_
    return {
        'left': t.children_left.tolist(),
        'right': t.children_right.tolist(),
        'feature': t.feature.tolist(),
        'threshold': [float(v) for v in t.threshold],
        'value': [float(v) for v in t.value[:, 0, 0]],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--csv', required=True)
    ap.add_argument('--out', default=os.path.join(ROOT, 'assets', 'models'))
    args = ap.parse_args()

    X, y, baseline, df = load(args.csv)
    print(f'{len(X)} sessions loaded; calories {y.min():.0f}-{y.max():.0f} (mean {y.mean():.0f})')

    X_tr, X_te, y_tr, y_te, b_tr, b_te = train_test_split(X, y, baseline, test_size=0.2, random_state=42)

    gb = GradientBoostingRegressor(n_estimators=250, learning_rate=0.05, max_depth=3, subsample=0.8,
                                   min_samples_leaf=5, random_state=42)
    gb.fit(X_tr, y_tr)

    lin = LinearRegression().fit(X_tr, y_tr)

    print('\n=== Held-out test set (20%) ===')
    m_met = report('Compendium MET baseline (app today)', y_te, b_te)
    m_lin = report('Linear regression', y_te, lin.predict(X_te))
    m_gb = report('Gradient Boosting', y_te, gb.predict(X_te))

    cv_pred = cross_val_predict(
        GradientBoostingRegressor(n_estimators=250, learning_rate=0.05, max_depth=3, subsample=0.8,
                                  min_samples_leaf=5, random_state=42),
        X, y, cv=KFold(5, shuffle=True, random_state=1))
    print('\n=== 5-fold cross-validation (all data) ===')
    m_cv = report('Gradient Boosting (CV)', y, cv_pred)
    report('Compendium MET baseline', y, baseline)

    imp = sorted(zip(FEATURES, gb.feature_importances_), key=lambda p: -p[1])
    print('\nfeature importance:', ', '.join(f'{n} {v:.2f}' for n, v in imp[:6]))

    beats = m_gb['mae'] < m_met['mae']
    print('\nGradient Boosting beats the MET baseline on held-out MAE:', beats)

    meta = {
        'name': 'calorie_gb',
        'version': datetime.now(timezone.utc).strftime('%Y%m%d'),
        'trained_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'algorithm': 'GradientBoostingRegressor (scikit-learn), squared error',
        'target': 'calories burned in one workout session (kcal)',
        'data': {
            'name': 'Gym Members Exercise Dataset',
            'source': 'https://www.kaggle.com/datasets/valakhorasani/gym-members-exercise-dataset',
            'rows_used': int(len(X)),
            'caveat': 'Small dataset of unclear provenance; prototype only.',
        },
        'features': FEATURES,
        'workout_types': TYPES,
        'learning_rate': gb.learning_rate,
        'init': float(gb.init_.constant_[0][0]) if hasattr(gb.init_, 'constant_') else float(y_tr.mean()),
        'trees': [tree_to_dict(e[0]) for e in gb.estimators_],
        'metrics': {'test': {'compendium_met': m_met, 'linear': m_lin, 'gradient_boosting': m_gb},
                    'cross_validation': m_cv, 'beats_met_baseline': bool(beats)},
        'baseline_mets': COMPENDIUM_MET,
    }
    rng = np.random.RandomState(3)
    idx = rng.choice(len(X_te), 10, replace=False)
    meta['test_vectors'] = [
        {'x': [float(v) for v in X_te.iloc[i].tolist()], 'kcal': float(gb.predict(X_te.iloc[[i]])[0])} for i in idx
    ]

    if not beats:
        print('\nNOT exporting: the model does not improve on the Compendium baseline, so the app keeps using METs.')
        return
    os.makedirs(args.out, exist_ok=True)
    path = os.path.join(args.out, 'calorie_gb.json')
    with open(path, 'w') as f:
        json.dump(meta, f)
    print('wrote', path, '(%d KB)' % (os.path.getsize(path) // 1024))


if __name__ == '__main__':
    main()
