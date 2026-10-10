#!/usr/bin/env python3
"""Local end-to-end check of the food-classifier pipeline on tiny SYNTHETIC images.

It does NOT produce a useful model. It proves, in a minute and without any dataset, that
class mapping -> tf.data -> training -> TFLite export -> TFLite inference all work, so
the real Kaggle run is unlikely to fail at the export step.

  ml/.venv/bin/python ml/food_classifier/smoke_test.py
"""
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CLASSES = {'roti': (200, 170, 110), 'samosa': (170, 110, 40), 'daal': (230, 190, 40), 'kheer': (240, 240, 235)}


def main():
    rng = np.random.RandomState(0)
    with tempfile.TemporaryDirectory() as tmp:
        custom = os.path.join(tmp, 'custom')
        for name, color in CLASSES.items():
            os.makedirs(os.path.join(custom, name))
            for i in range(40):
                base = np.full((96, 96, 3), color, dtype=np.float32)
                noise = rng.normal(0, 25, base.shape)
                Image.fromarray(np.clip(base + noise, 0, 255).astype(np.uint8)).save(os.path.join(custom, name, f'{i}.jpg'))
        out = os.path.join(tmp, 'out')
        cmd = [sys.executable, os.path.join(HERE, 'train_kaggle.py'), '--custom', custom, '--out', out,
               '--weights', 'none', '--epochs-head', '2', '--epochs-ft', '0', '--batch', '8', '--min-per-class', '20']
        subprocess.run(cmd, check=True, cwd=HERE)

        tflite = os.path.join(out, 'food_classifier.tflite')
        meta = json.load(open(os.path.join(out, 'food_classifier_labels.json')))
        assert os.path.getsize(tflite) > 100_000, 'TFLite file is suspiciously small'
        assert meta['labels'] == sorted(CLASSES), meta['labels']
        print('\nSMOKE TEST PASSED: exported %.1f MB TFLite model with labels %s' % (os.path.getsize(tflite) / 1e6, meta['labels']))


if __name__ == '__main__':
    main()
