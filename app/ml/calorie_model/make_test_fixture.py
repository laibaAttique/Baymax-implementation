#!/usr/bin/env python3
"""Builds test/fixtures/tiny_gb.json — a small model trained on SYNTHETIC data.

Used only by the Dart unit test to prove the Dart tree evaluator matches scikit-learn
exactly. It is not shipped in the app and says nothing about real calorie burn.
"""
import json, os
import numpy as np
from sklearn.ensemble import GradientBoostingRegressor

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
rng = np.random.RandomState(0)
X = np.column_stack([rng.uniform(18, 60, 600), rng.randint(0, 2, 600), rng.uniform(50, 110, 600), rng.uniform(1.5, 1.95, 600),
                     rng.uniform(0.3, 2.0, 600), rng.randint(1, 4, 600), *np.eye(4)[rng.randint(0, 4, 600)].T])
y = 6 * X[:, 2] * X[:, 4] + 40 * X[:, 5] + 30 * X[:, 6] + rng.normal(0, 20, 600)
gb = GradientBoostingRegressor(n_estimators=40, max_depth=3, learning_rate=0.1, random_state=0).fit(X, y)

def tree(est):
    t = est.tree_
    return {'left': t.children_left.tolist(), 'right': t.children_right.tolist(), 'feature': t.feature.tolist(),
            'threshold': [float(v) for v in t.threshold], 'value': [float(v) for v in t.value[:, 0, 0]]}

model = {
    'features': ['age', 'sex_male', 'weight_kg', 'height_m', 'duration_h', 'experience', 'is_cardio', 'is_hiit', 'is_strength', 'is_yoga'],
    'workout_types': ['Cardio', 'HIIT', 'Strength', 'Yoga'],
    'learning_rate': gb.learning_rate,
    'init': float(gb.init_.constant_[0][0]),
    'trees': [tree(e[0]) for e in gb.estimators_],
    'test_vectors': [{'x': [float(v) for v in X[i]], 'kcal': float(gb.predict(X[[i]])[0])} for i in range(0, 600, 60)],
    'note': 'SYNTHETIC test fixture - not a real calorie model',
}
out = os.path.join(ROOT, 'test', 'fixtures', 'tiny_gb.json')
os.makedirs(os.path.dirname(out), exist_ok=True)
json.dump(model, open(out, 'w'))
print('wrote', out, os.path.getsize(out) // 1024, 'KB')
