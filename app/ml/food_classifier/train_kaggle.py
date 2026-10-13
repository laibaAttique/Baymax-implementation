#!/usr/bin/env python3
"""Module 7 — MobileNetV2 food classifier -> TensorFlow Lite.

Transfer learning: ImageNet-pretrained MobileNetV2, new classification head, then
fine-tune the top layers. Trains only on classes that map to a food in the app's
catalogue (see class_map.py), exports a small TFLite model + labels.json.

RECOMMENDED: run clean_images.py first, then train with  --prepared <clean folder>.

DATASETS (download links are in ml/README.md)
  --food101  Food-101 root (the folder that contains `images/`, ideally also `meta/`)
             Kaggle copy: https://www.kaggle.com/datasets/kmader/food41  -> /kaggle/input/food41
  --extra    folder(s) of class-named sub-folders (Indian / South-Asian sets, e.g. Khana or the
             Hugging Face rajistics/indian_food_images export). Repeatable.
  --custom   folder whose sub-folders are already named with catalogue ids (your own photos,
             e.g. Pakistani dishes: biryani photos in custom/chicken_biryani/)

KAGGLE (GPU T4 x2, ~1.5-3 h for ~15k images):
  Add the datasets in the notebook sidebar, then:
    !python train_kaggle.py --food101 /kaggle/input/food41 --out /kaggle/working
  Download food_classifier.tflite and food_classifier_labels.json from /kaggle/working and put both in
  the app's assets/models/ folder.

LOCAL (CPU is slow; use --limit-per-class 100 --epochs-head 3 --epochs-ft 0 for a trial):
  ml/.venv/bin/python ml/food_classifier/train_kaggle.py --food101 /path/food-101 --out ml/food_classifier/out
"""
import argparse
import json
import os
import random
from collections import Counter, defaultdict
from datetime import datetime, timezone

import numpy as np
import tensorflow as tf

from class_map import FOOD101, SUGGESTED_NEW_FOODS, resolve

IMG = 224
IMAGE_EXT = ('.jpg', '.jpeg', '.png', '.webp', '.bmp')
AUTOTUNE = tf.data.AUTOTUNE


# ---------------------------------------------------------------- data discovery
def list_images(folder):
    return [os.path.join(folder, f) for f in sorted(os.listdir(folder)) if f.lower().endswith(IMAGE_EXT)]


def find_food101_images(root):
    """The Kaggle copies differ in layout; look for the folder that contains `apple_pie/`."""
    for dirpath, dirnames, _ in os.walk(root):
        if 'apple_pie' in dirnames and 'ramen' in dirnames:
            return dirpath
    return None


def collect_food101(root, files_by_label, report):
    images = find_food101_images(root)
    if images is None:
        raise SystemExit(f'--food101: could not find the Food-101 class folders (apple_pie/, ramen/, ...) under {root}')
    print('Food-101 images found in', images)
    for cls in sorted(os.listdir(images)):
        path = os.path.join(images, cls)
        if not os.path.isdir(path):
            continue
        label = FOOD101.get(cls)
        if label:
            files_by_label[label] += [(p, 'food101') for p in list_images(path)]
            report['food101_used'].append(f'{cls} -> {label}')
        else:
            report['food101_skipped'].append(cls)


def collect_extra(root, files_by_label, report, custom=False):
    for cls in sorted(os.listdir(root)):
        path = os.path.join(root, cls)
        if not os.path.isdir(path):
            continue
        label = cls if custom else resolve(cls)
        if label:
            files_by_label[label] += [(p, os.path.basename(root.rstrip('/'))) for p in list_images(path)]
            report['extra_used'].append(f'{cls} -> {label}')
        else:
            report['extra_unmapped'].append(cls)


# ---------------------------------------------------------------- tf.data
def make_dataset(items, labels, training, batch):
    paths = [p for p, _ in items]
    ys = [labels.index(l) for _, l in items]

    def load(path, y):
        img = tf.io.decode_image(tf.io.read_file(path), channels=3, expand_animations=False)
        img = tf.image.resize(img, (IMG, IMG), antialias=True)
        img.set_shape((IMG, IMG, 3))
        return tf.cast(img, tf.float32), y

    ds = tf.data.Dataset.from_tensor_slices((paths, ys))
    if training:
        ds = ds.shuffle(len(paths), seed=1, reshuffle_each_iteration=True)
    ds = ds.map(load, num_parallel_calls=AUTOTUNE)
    return ds.batch(batch).prefetch(AUTOTUNE)


def build_model(n_classes, weights):
    augment = tf.keras.Sequential([
        tf.keras.layers.RandomFlip('horizontal'),
        tf.keras.layers.RandomRotation(0.08),
        tf.keras.layers.RandomZoom(0.15),
        tf.keras.layers.RandomContrast(0.15),
    ], name='augment')
    base = tf.keras.applications.MobileNetV2(input_shape=(IMG, IMG, 3), include_top=False,
                                             weights=None if weights == 'none' else 'imagenet')
    base.trainable = False
    inputs = tf.keras.Input((IMG, IMG, 3), name='image_rgb_0_255')
    x = augment(inputs)
    x = tf.keras.layers.Rescaling(1 / 127.5, offset=-1, name='to_minus1_1')(x)  # MobileNetV2 preprocessing
    x = base(x, training=False)
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dropout(0.3)(x)
    outputs = tf.keras.layers.Dense(n_classes, activation='softmax', name='probabilities')(x)
    return tf.keras.Model(inputs, outputs), base


def compile_model(model, lr):
    model.compile(optimizer=tf.keras.optimizers.Adam(lr),
                  loss=tf.keras.losses.SparseCategoricalCrossentropy(),
                  metrics=['accuracy', tf.keras.metrics.SparseTopKCategoricalAccuracy(3, name='top3')])


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--prepared', help='folder produced by clean_images.py (images/, split.csv, labels.json) — recommended')
    ap.add_argument('--food101')
    ap.add_argument('--extra', action='append', default=[])
    ap.add_argument('--custom', action='append', default=[])
    ap.add_argument('--out', default='out')
    ap.add_argument('--weights', choices=['imagenet', 'none'], default='imagenet')
    ap.add_argument('--epochs-head', type=int, default=6)
    ap.add_argument('--epochs-ft', type=int, default=8)
    ap.add_argument('--batch', type=int, default=32)
    ap.add_argument('--max-per-class', type=int, default=600)
    ap.add_argument('--limit-per-class', type=int, default=0, help='cap images per class (quick trials)')
    ap.add_argument('--min-per-class', type=int, default=30)
    args = ap.parse_args()
    random.seed(7)
    os.makedirs(args.out, exist_ok=True)

    files, report = defaultdict(list), defaultdict(list)
    dropped = []
    if args.prepared:
        # Cleaned dataset with a fixed, leakage-free train/validation split.
        import csv
        train, val = [], []
        with open(os.path.join(args.prepared, 'split.csv')) as fh:
            for r in csv.DictReader(fh):
                item = (os.path.join(args.prepared, r['path']), r['label'])
                (train if r['split'] == 'train' else val).append(item)
                files[r['label']].append((item[0], 'prepared'))
        if args.limit_per_class:  # quick trials only
            def limited(items):
                seen = Counter()
                out = []
                for p, l in items:
                    if seen[l] < args.limit_per_class:
                        seen[l] += 1
                        out.append((p, l))
                return out
            train, val = limited(train), limited(val)
        labels = sorted(files)
        random.shuffle(train)
    else:
        if args.food101:
            collect_food101(args.food101, files, report)
        for r in args.extra:
            collect_extra(r, files, report)
        for r in args.custom:
            collect_extra(r, files, report, custom=True)
        if not files:
            raise SystemExit('No training images found. Pass --prepared, --food101, --extra or --custom.')

        cap = args.limit_per_class or args.max_per_class
        labels = sorted(l for l, v in files.items() if len(v) >= args.min_per_class)
        dropped = sorted(set(files) - set(labels))
        train, val = [], []
        for l in labels:
            items = files[l][:]
            random.shuffle(items)
            items = items[:cap]
            n_val = max(1, int(0.15 * len(items)))
            val += [(p, l) for p, _ in items[:n_val]]
            train += [(p, l) for p, _ in items[n_val:]]
        random.shuffle(train)

    print(f'\n{len(labels)} classes, {len(train)} train / {len(val)} val images')
    for l in labels:
        srcs = Counter(s for _, s in files[l])
        print(f'  {l:20s} {len(files[l]):5d} images  {dict(srcs)}')
    if dropped:
        print('dropped (too few images):', dropped)
    if report['extra_unmapped']:
        print('\nUnmapped folders in --extra (add them to class_map.SYNONYMS if they match a catalogue food):')
        print('  ', ', '.join(report['extra_unmapped']))
    print('Foods the datasets have that the catalogue lacks (consider adding):', ', '.join(SUGGESTED_NEW_FOODS))

    train_ds = make_dataset(train, labels, True, args.batch)
    val_ds = make_dataset(val, labels, False, args.batch)

    counts = Counter(l for _, l in train)
    class_weight = {i: len(train) / (len(labels) * counts[l]) for i, l in enumerate(labels)}

    model, base = build_model(len(labels), args.weights)
    compile_model(model, 1e-3)
    cb = [tf.keras.callbacks.EarlyStopping(monitor='val_accuracy', patience=3, restore_best_weights=True),
          tf.keras.callbacks.ReduceLROnPlateau(monitor='val_loss', factor=0.5, patience=1)]
    print('\n--- Stage 1: train the new head ---')
    model.fit(train_ds, validation_data=val_ds, epochs=args.epochs_head, class_weight=class_weight, callbacks=cb)

    if args.epochs_ft > 0:
        print('\n--- Stage 2: fine-tune the top MobileNetV2 layers ---')
        base.trainable = True
        for layer in base.layers[:-40]:
            layer.trainable = False
        for layer in base.layers:  # keep BatchNorm statistics frozen
            if isinstance(layer, tf.keras.layers.BatchNormalization):
                layer.trainable = False
        compile_model(model, 1e-4)
        model.fit(train_ds, validation_data=val_ds, epochs=args.epochs_ft, class_weight=class_weight, callbacks=cb)

    loss, acc, top3 = model.evaluate(val_ds, verbose=0)
    print(f'\nKeras validation: top-1 {acc:.3f} | top-3 {top3:.3f}')

    # Per-class accuracy
    y_true, y_pred = [], []
    for x, y in val_ds:
        y_true += y.numpy().tolist()
        y_pred += model.predict(x, verbose=0).argmax(1).tolist()
    per_class = {l: float(np.mean([p == t for p, t in zip(y_pred, y_true) if t == i]) if i in y_true else 0.0)
                 for i, l in enumerate(labels)}

    # ---- Export TFLite (float16 weights ~ half the size, accuracy unchanged in practice)
    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    conv.optimizations = [tf.lite.Optimize.DEFAULT]
    conv.target_spec.supported_types = [tf.float16]
    tflite_path = os.path.join(args.out, 'food_classifier.tflite')
    open(tflite_path, 'wb').write(conv.convert())

    # ---- Verify the exported model on (up to) 400 validation images
    it = tf.lite.Interpreter(model_path=tflite_path)
    it.allocate_tensors()
    inp, outp = it.get_input_details()[0], it.get_output_details()[0]
    hits = total = agree = 0
    for x, y in val_ds.unbatch().take(400):
        img = x.numpy()[None].astype(np.float32)
        it.set_tensor(inp['index'], img)
        it.invoke()
        tflite_pred = int(it.get_tensor(outp['index'])[0].argmax())
        keras_pred = int(model.predict(img, verbose=0)[0].argmax())
        hits += int(tflite_pred == int(y))
        agree += int(tflite_pred == keras_pred)
        total += 1
    tflite_acc = hits / max(total, 1)
    agreement = agree / max(total, 1)
    print(f'TFLite check on {total} val images: top-1 {tflite_acc:.3f}  ({os.path.getsize(tflite_path) / 1e6:.1f} MB)')
    print(f'TFLite and Keras give the same answer on {agreement:.1%} of images')
    assert agreement >= 0.95, 'The exported TFLite model disagrees with the trained model; do not ship it.'

    meta = {
        'name': 'food_classifier',
        'version': datetime.now(timezone.utc).strftime('%Y%m%d'),
        'trained_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'architecture': 'MobileNetV2 (transfer learning), float16 TFLite',
        'input': {'size': IMG, 'channels': 'RGB', 'dtype': 'float32', 'range': '0-255 (rescaling is inside the model)'},
        'labels': labels,
        'metrics': {'keras_top1': float(acc), 'keras_top3': float(top3), 'tflite_top1_sample': tflite_acc, 'tflite_keras_agreement': agreement,
                    'val_images': len(val), 'train_images': len(train), 'per_class_top1': per_class},
        'datasets': sorted({s for v in files.values() for _, s in v}),
        'notes': 'Labels are food-catalogue ids (assets/data/foods.json). Estimates only: portion size is not predicted.',
    }
    with open(os.path.join(args.out, 'food_classifier_labels.json'), 'w') as f:
        json.dump(meta, f, indent=1)
    print('\nwrote', tflite_path, 'and food_classifier_labels.json')


if __name__ == '__main__':
    main()
