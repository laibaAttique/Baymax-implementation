#!/usr/bin/env python3
"""Module 2 — Logistic Regression health-risk classifier.

Data: CDC Diabetes Health Indicators (UCI id 891) — 253,680 adults from the CDC's BRFSS
telephone health survey (US, self-reported). The survey year is stated inconsistently
(UCI's summary links the 2014 BRFSS page; the Kaggle copy says 2015), so the year is not
asserted here. Check the UCI page for the license terms.
  https://archive.ics.uci.edu/dataset/891/cdc+diabetes+health+indicators

What it learns
--------------
From the four inputs the scope document names — BMI, age, sex, activity — it estimates
which of six categories people like this most resemble:
    Healthy, Overweight, Obese, At-Risk, Cardiac, Diabetic
Labels are derived from the survey answers with the same priority the app's rule engine uses:
    heart disease/attack -> Cardiac
    diabetes             -> Diabetic
    high BP or cholesterol -> At-Risk
    else by WHO BMI band -> Obese (>=30) / Overweight (>=25) / Healthy

IMPORTANT: demographics only weakly predict disease, so this is a *risk screen*, not a
diagnosis. The model is trained with balanced class weights so rare classes can be predicted;
`priors` are exported so the app can recover calibrated probabilities.

Run:  ml/.venv/bin/python ml/health_classifier/train.py
Output (app): assets/models/health_classifier.json + health_classifier.tflite
"""
import argparse
import json
import os
from datetime import datetime, timezone

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report, confusion_matrix, f1_score, roc_auc_score
from sklearn.model_selection import train_test_split

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
DEFAULT_CSV = os.path.join(ROOT, 'ml', 'data', 'cdc_diabetes_health_indicators.csv')
DEFAULT_OUT = os.path.join(ROOT, 'assets', 'models')

CLASSES = ['Healthy', 'Overweight', 'Obese', 'At-Risk', 'Cardiac', 'Diabetic']
FEATURES = ['bmi', 'age', 'sex_male', 'active', 'bmi_sq', 'age_sq']

# BRFSS age categories 1..13 -> mid-point of each 5-year band (13 = 80+)
AGE_MID = {1: 21, 2: 27, 3: 32, 4: 37, 5: 42, 6: 47, 7: 52, 8: 57, 9: 62, 10: 67, 11: 72, 12: 77, 13: 82}


def label_row(df: pd.DataFrame) -> pd.Series:
    y = np.select(
        [
            df['HeartDiseaseorAttack'] == 1,
            df['Diabetes_binary'] == 1,
            (df['HighBP'] == 1) | (df['HighChol'] == 1),
            df['BMI'] >= 30,
            df['BMI'] >= 25,
        ],
        ['Cardiac', 'Diabetic', 'At-Risk', 'Obese', 'Overweight'],
        default='Healthy',
    )
    return pd.Series(y, index=df.index)


def make_features(bmi, age, sex_male, active):
    bmi = np.asarray(bmi, dtype=np.float64)
    age = np.asarray(age, dtype=np.float64)
    return np.column_stack([bmi, age, sex_male, active, bmi ** 2, age ** 2])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--csv', default=DEFAULT_CSV)
    ap.add_argument('--out', default=DEFAULT_OUT)
    ap.add_argument('--no-tflite', action='store_true', help='skip the TFLite export')
    args = ap.parse_args()

    df = pd.read_csv(args.csv)
    df = df[(df['BMI'] >= 12) & (df['BMI'] <= 70)].copy()  # drop implausible values
    df['label'] = label_row(df)
    df['age_years'] = df['Age'].map(AGE_MID)

    X = make_features(df['BMI'], df['age_years'], df['Sex'], df['PhysActivity'])
    y = df['label'].map({c: i for i, c in enumerate(CLASSES)}).to_numpy()

    X_tr, X_te, y_tr, y_te = train_test_split(X, y, test_size=0.2, random_state=42, stratify=y)

    mean, scale = X_tr.mean(axis=0), X_tr.std(axis=0)
    Z_tr, Z_te = (X_tr - mean) / scale, (X_te - mean) / scale

    priors = np.bincount(y_tr, minlength=len(CLASSES)) / len(y_tr)

    clf = LogisticRegression(solver='lbfgs', C=1.0, max_iter=2000, class_weight='balanced')
    clf.fit(Z_tr, y_tr)

    proba_bal = clf.predict_proba(Z_te)
    pred = proba_bal.argmax(axis=1)

    # Calibrated probabilities: undo the class-weight reweighting with the priors.
    def calibrate(p):
        q = p * priors
        return q / q.sum(axis=1, keepdims=True)

    proba = calibrate(proba_bal)

    print('\n=== Test set (20%%, n=%d) ===' % len(y_te))
    print(classification_report(y_te, pred, target_names=CLASSES, digits=3, zero_division=0))
    print('confusion matrix (rows=true, cols=predicted):')
    print(pd.DataFrame(confusion_matrix(y_te, pred), index=CLASSES, columns=CLASSES))

    # How well do the calibrated probabilities rank people with / without each disease?
    auc = {}
    for name in ['Cardiac', 'Diabetic']:
        i = CLASSES.index(name)
        auc[name] = float(roc_auc_score((y_te == i).astype(int), proba[:, i]))
    print('\nROC-AUC (calibrated probability of the class vs rest):', auc)

    # Risk-flag thresholds: the lowest probability that (a) flags at most MAX_FLAGGED_SHARE of
    # people, so "At-Risk" stays meaningful, and (b) has precision of at least 2x the base rate.
    MAX_FLAGGED_SHARE = 0.15
    thresholds, flag_stats = {}, {}
    for name in ['Cardiac', 'Diabetic']:
        i = CLASSES.index(name)
        truth = (y_te == i)
        base = float(truth.mean())
        best = None
        for t in np.arange(0.05, 0.95, 0.005):
            flagged = proba[:, i] >= t
            if flagged.sum() < 200:
                break
            if flagged.mean() > MAX_FLAGGED_SHARE:
                continue
            precision = float(truth[flagged].mean())
            if precision >= 2 * base:
                best = (float(round(t, 3)), precision, float(truth[flagged].sum() / truth.sum()), int(flagged.sum()))
                break
        thresholds[name] = best[0] if best else None
        flag_stats[name] = {
            'base_rate': round(base, 4),
            'threshold': best[0] if best else None,
            'precision_at_threshold': round(best[1], 4) if best else None,
            'recall_at_threshold': round(best[2], 4) if best else None,
            'share_of_people_flagged': round(best[3] / len(y_te), 4) if best else 0,
        }
    print('\nrisk-flag thresholds (precision >= 2x base rate):')
    for k, v in flag_stats.items():
        print(' ', k, v)

    metrics = {
        'test_rows': int(len(y_te)),
        'accuracy': float((pred == y_te).mean()),
        'macro_f1': float(f1_score(y_te, pred, average='macro')),
        'roc_auc': auc,
        'risk_flags': flag_stats,
    }

    coef = clf.coef_  # (6, F), applies to standardised features
    intercept = clf.intercept_
    meta = {
        'name': 'health_classifier',
        'version': datetime.now(timezone.utc).strftime('%Y%m%d'),
        'trained_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'algorithm': 'multinomial logistic regression (scikit-learn, lbfgs, class_weight=balanced)',
        'data': {
            'name': 'CDC Diabetes Health Indicators (CDC BRFSS survey)',
            'source': 'https://archive.ics.uci.edu/dataset/891/cdc+diabetes+health+indicators',
            'license': 'see the UCI dataset page',
            'year_note': 'UCI links the 2014 BRFSS page; the Kaggle copy says 2015',
            'rows_used': int(len(df)),
            'population': 'US adults, self-reported survey data',
        },
        'inputs': ['bmi', 'age_years', 'sex_male (0/1)', 'active (0/1)'],
        'classes': CLASSES,
        'features': FEATURES,
        'mean': mean.tolist(),
        'scale': scale.tolist(),
        'coef': coef.tolist(),
        'intercept': intercept.tolist(),
        'priors': priors.tolist(),
        'thresholds': thresholds,
        'metrics': metrics,
        'limitations': [
            'Trained on US survey data (BRFSS, 2014/2015); not validated for South Asian populations, who tend to have higher diabetes risk at lower BMI.',
            'Uses only BMI, age, sex and a yes/no activity flag, so it estimates statistical risk and cannot diagnose anyone.',
        ],
    }

    # Test vectors so the Dart implementation can be checked against this exact model.
    rng = np.random.RandomState(7)
    idx = rng.choice(len(X_te), 12, replace=False)
    meta['test_vectors'] = [
        {
            'bmi': float(X_te[i, 0]), 'age': float(X_te[i, 1]), 'sex_male': float(X_te[i, 2]), 'active': float(X_te[i, 3]),
            'proba_balanced': [float(v) for v in proba_bal[i]],
            'proba_calibrated': [float(v) for v in proba[i]],
        }
        for i in idx
    ]

    os.makedirs(args.out, exist_ok=True)
    json_path = os.path.join(args.out, 'health_classifier.json')
    with open(json_path, 'w') as f:
        json.dump(meta, f, indent=1)
    print('\nwrote', json_path)

    if not args.no_tflite:
        export_tflite(meta, os.path.join(args.out, 'health_classifier.tflite'), X_te[idx], proba_bal[idx])


def export_tflite(meta, path, X_check, proba_check):
    """Softmax regression as a TFLite graph: raw [bmi, age, sex, active] -> 6 probabilities."""
    import tensorflow as tf

    mean = tf.constant(meta['mean'], tf.float32)
    scale = tf.constant(meta['scale'], tf.float32)
    w = tf.constant(np.array(meta['coef'], dtype=np.float32).T)
    b = tf.constant(meta['intercept'], tf.float32)

    class Model(tf.Module):
        @tf.function(input_signature=[tf.TensorSpec([1, 4], tf.float32, name='bmi_age_sex_active')])
        def serve(self, x):
            bmi, age = x[:, 0:1], x[:, 1:2]
            feats = tf.concat([x, tf.square(bmi), tf.square(age)], axis=1)
            z = (feats - mean) / scale
            return {'probabilities': tf.nn.softmax(tf.matmul(z, w) + b)}

    m = Model()
    conv = tf.lite.TFLiteConverter.from_concrete_functions([m.serve.get_concrete_function()], m)
    open(path, 'wb').write(conv.convert())
    print('wrote', path, '(%d bytes)' % os.path.getsize(path))

    # Verify the TFLite model reproduces scikit-learn.
    it = tf.lite.Interpreter(model_path=path)
    it.allocate_tensors()
    inp, out = it.get_input_details()[0], it.get_output_details()[0]
    worst = 0.0
    for row, expected in zip(X_check, proba_check):
        it.set_tensor(inp['index'], row[:4].reshape(1, 4).astype(np.float32))
        it.invoke()
        worst = max(worst, float(np.abs(it.get_tensor(out['index'])[0] - expected).max()))
    print('max |TFLite - scikit-learn| over %d samples: %.2e' % (len(X_check), worst))
    assert worst < 1e-4, 'TFLite model does not match scikit-learn'


if __name__ == '__main__':
    main()
