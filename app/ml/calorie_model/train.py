#!/usr/bin/env python3
"""Module 3 — Gradient Boosting workout-calorie model, with a physiology safety gate.

Trains scikit-learn's GradientBoostingRegressor to predict calories burned in one session
from inputs the Baymax app has (age, sex, weight, height, session length, experience level,
workout type — NO heart rate), and compares it with the Compendium-of-Physical-Activities
MET estimate the app uses today.

A model is exported to the app ONLY if all of these hold:
  1. it is more accurate than the MET estimate on held-out data;
  2. it respects physiology: for a standard person (30 y, 70 kg, 1 h) each workout type's
     prediction is within 0.5x-2x of the Compendium value, and heavier people burn more;
So accuracy on a dataset alone can never push a physiologically wrong model into the app.

Data: clean/gym_members_clean.csv, produced by clean_data.py from the Kaggle
"Gym Members Exercise Dataset" (a raw gym_members_exercise_tracking.csv also works).

Kaggle:  !python train.py --csv /kaggle/input/<your-dataset>/gym_members_clean.csv --out /kaggle/working
Local:   ml/.venv/bin/python ml/calorie_model/train.py --csv clean/gym_members_clean.csv --out ml/calorie_model/out
Output:  calorie_model_report.json (always) and calorie_gb.json (only if every check passes)
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

# 2024 Adult Compendium of Physical Activities (pacompendium.com); MET = kcal per kg per hour
COMPENDIUM_MET = {'Yoga': 2.3, 'Strength': 3.5, 'Cardio': 7.3, 'HIIT': 7.5}  # 02175, 02054, 02000, 02040
PLAUSIBLE_RATIO = (0.5, 2.0)
TYPES = ['Cardio', 'HIIT', 'Strength', 'Yoga']
FEATURES = ['age', 'sex_male', 'weight_kg', 'height_m', 'duration_h', 'experience',
            'is_cardio', 'is_hiit', 'is_strength', 'is_yoga']

RAW_TO_CLEAN = {
    'Age': 'age', 'Gender': 'gender', 'Weight (kg)': 'weight_kg', 'Height (m)': 'height_m',
    'Session_Duration (hours)': 'duration_h', 'Calories_Burned': 'calories_burned',
    'Workout_Type': 'workout_type', 'Experience_Level': 'experience_level',
}


def find_csv(path):
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
    df = df.rename(columns=lambda c: RAW_TO_CLEAN.get(c.strip(), c.strip()))
    need = ['age', 'gender', 'weight_kg', 'height_m', 'duration_h', 'calories_burned', 'workout_type', 'experience_level']
    missing = [c for c in need if c not in df.columns]
    if missing:
        raise SystemExit(f'CSV is missing columns {missing}. Found: {list(df.columns)}')
    df = df.dropna(subset=need)
    X = pd.DataFrame({
        'age': df['age'],
        'sex_male': (df['gender'].str.strip().str.lower() == 'male').astype(int),
        'weight_kg': df['weight_kg'],
        'height_m': df['height_m'],
        'duration_h': df['duration_h'],
        'experience': df['experience_level'],
        **{f'is_{t.lower()}': (df['workout_type'] == t).astype(int) for t in TYPES},
    })[FEATURES]
    y = df['calories_burned'].astype(float)
    baseline = df['workout_type'].map(COMPENDIUM_MET).astype(float) * df['weight_kg'] * df['duration_h']
    return X, y, baseline


def row(weight=70.0, wtype='Cardio'):
    """A standard person: 30-year-old man, 1.75 m, experience 2, one hour."""
    return pd.DataFrame([{
        'age': 30, 'sex_male': 1, 'weight_kg': weight, 'height_m': 1.75, 'duration_h': 1.0, 'experience': 2,
        **{f'is_{t.lower()}': int(t == wtype) for t in TYPES},
    }])[FEATURES]


def physiology_check(model):
    """Does the model agree with published energy costs? Returns (passed, details)."""
    details, ok = {}, True
    for t in TYPES:
        pred = float(model.predict(row(70.0, t))[0])
        expected = COMPENDIUM_MET[t] * 70.0
        ratio = pred / expected
        within = PLAUSIBLE_RATIO[0] <= ratio <= PLAUSIBLE_RATIO[1]
        ok &= within
        details[t] = {'model_kcal_per_hour_70kg': round(pred), 'compendium_kcal_per_hour_70kg': round(expected),
                      'ratio': round(ratio, 2), 'within_0.5x_to_2x': within}
    heavier = float(model.predict(row(95.0, 'Cardio'))[0]) > float(model.predict(row(55.0, 'Cardio'))[0])
    details['heavier_people_burn_more'] = heavier
    return bool(ok and heavier), details


def report(name, y_true, y_pred):
    mae = mean_absolute_error(y_true, y_pred)
    rmse = mean_squared_error(y_true, y_pred) ** 0.5
    r2 = r2_score(y_true, y_pred)
    print(f'  {name:36s} MAE {mae:7.1f} kcal | RMSE {rmse:7.1f} | R2 {r2:6.3f}')
    return {'mae': float(mae), 'rmse': float(rmse), 'r2': float(r2)}


def tree_to_dict(est):
    t = est.tree_
    return {'left': t.children_left.tolist(), 'right': t.children_right.tolist(), 'feature': t.feature.tolist(),
            'threshold': [float(v) for v in t.threshold], 'value': [float(v) for v in t.value[:, 0, 0]]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--csv', required=True, help='gym_members_clean.csv (or the raw Kaggle CSV, or a folder holding it)')
    ap.add_argument('--out', default='out')
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    X, y, baseline = load(args.csv)
    print(f'{len(X)} sessions; calories {y.min():.0f}-{y.max():.0f} (mean {y.mean():.0f})')

    X_tr, X_te, y_tr, y_te, b_tr, b_te = train_test_split(X, y, baseline, test_size=0.2, random_state=42)
    params = dict(n_estimators=250, learning_rate=0.05, max_depth=3, subsample=0.8, min_samples_leaf=5, random_state=42)
    gb = GradientBoostingRegressor(**params).fit(X_tr, y_tr)
    lin = LinearRegression().fit(X_tr, y_tr)

    print('\n=== Held-out test set (20%) ===')
    m_met = report('Compendium MET x kg x hours (app)', y_te, b_te)
    m_lin = report('Linear regression', y_te, lin.predict(X_te))
    m_gb = report('Gradient Boosting', y_te, gb.predict(X_te))
    cv_pred = cross_val_predict(GradientBoostingRegressor(**params), X, y, cv=KFold(5, shuffle=True, random_state=1))
    print('\n=== 5-fold cross-validation (all rows) ===')
    m_cv = report('Gradient Boosting (CV)', y, cv_pred)
    imp = sorted(zip(FEATURES, gb.feature_importances_), key=lambda p: -p[1])
    print('\nfeature importance:', ', '.join(f'{n} {v:.2f}' for n, v in imp[:6]))

    beats = m_gb['mae'] < m_met['mae']
    plausible, phys = physiology_check(gb)

    print('\n=== Physiology check (30-year-old man, 70 kg, one hour) ===')
    for t in TYPES:
        d = phys[t]
        print(f"  {t:9s} model {d['model_kcal_per_hour_70kg']:4d} kcal | Compendium {d['compendium_kcal_per_hour_70kg']:4d} kcal | "
              f"x{d['ratio']:<5} {'ok' if d['within_0.5x_to_2x'] else 'IMPLAUSIBLE'}")
    print('  heavier people burn more:', phys['heavier_people_burn_more'])

    export = beats and plausible
    print('\nMore accurate than the MET estimate on this data:', beats)
    print('Agrees with published energy costs:', plausible)
    if export:
        print('=> EXPORTING calorie_gb.json')
    else:
        why = []
        if not beats:
            why.append('it is not more accurate than the Compendium estimate')
        if not plausible:
            why.append('it contradicts published energy costs (the training data does, see cleaning_report.md)')
        print('=> NOT EXPORTING: ' + ' and '.join(why) + '. The app keeps using the Compendium MET estimate.')

    summary = {
        'trained_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'rows': int(len(X)),
        'metrics': {'test': {'compendium_met': m_met, 'linear': m_lin, 'gradient_boosting': m_gb}, 'cross_validation': m_cv},
        'more_accurate_than_met': bool(beats),
        'physiology_check': phys,
        'physiology_ok': plausible,
        'exported': bool(export),
    }
    with open(os.path.join(args.out, 'calorie_model_report.json'), 'w') as f:
        json.dump(summary, f, indent=1)
    print('wrote', os.path.join(args.out, 'calorie_model_report.json'))

    if not export:
        return

    meta = {
        'name': 'calorie_gb',
        'version': datetime.now(timezone.utc).strftime('%Y%m%d'),
        'trained_at': summary['trained_at'],
        'algorithm': 'GradientBoostingRegressor (scikit-learn), squared error',
        'target': 'calories burned in one workout session (kcal)',
        'features': FEATURES,
        'workout_types': TYPES,
        'learning_rate': gb.learning_rate,
        'init': float(gb.init_.constant_[0][0]),
        'trees': [tree_to_dict(e[0]) for e in gb.estimators_],
        'metrics': summary['metrics'],
        'physiology_check': phys,
        'baseline_mets': COMPENDIUM_MET,
    }
    idx = np.random.RandomState(3).choice(len(X_te), 10, replace=False)
    meta['test_vectors'] = [{'x': [float(v) for v in X_te.iloc[i].tolist()], 'kcal': float(gb.predict(X_te.iloc[[i]])[0])} for i in idx]
    path = os.path.join(args.out, 'calorie_gb.json')
    with open(path, 'w') as f:
        json.dump(meta, f)
    print('wrote', path, '(%d KB)' % (os.path.getsize(path) // 1024))


if __name__ == '__main__':
    main()
