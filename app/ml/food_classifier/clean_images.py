#!/usr/bin/env python3
"""Cleans a food-image dataset for the Baymax food recognizer (Module 7).

  python clean_images.py --src <extracted dataset> --out <clean folder> [--max-train 600]

What it does
  1. Finds class folders (Food-101 `images/<class>/`, or any `<class>/*.jpg` layout).
  2. Keeps only classes that map to a food in the app's catalogue (class_map.py), so every
     prediction has calories behind it. Unmapped classes are listed in the report.
  3. Checks every image: opens fully (no truncated/corrupt files), minimum size, sane aspect ratio.
  4. Removes exact duplicates (file hash) and near-duplicates (perceptual hash) inside a class,
     drops images that are near-identical across *different* classes (ambiguous labels), and
     drops any TRAINING image that is a near-copy of a VALIDATION image (data leakage).
  5. Split: if the dataset ships Food-101's official `meta/.../train.txt` + `test.txt`, the official
     TEST images become validation (the authors manually cleaned them; the training set is
     intentionally noisy). Otherwise a fixed random 85/15 split is used.
  6. Caps training images per class, shrinks images (longest side 384 px; the model uses 224) and
     writes images/<food_id>/NNNN.jpg, split.csv, labels.json and cleaning_report.md.
Nothing in the source folder is modified.
"""
import argparse
import csv
import hashlib
import json
import os
import random
from collections import Counter, defaultdict

from PIL import Image, ImageFile

from class_map import FOOD101, SUGGESTED_NEW_FOODS, SYNONYMS, normalise

ImageFile.LOAD_TRUNCATED_IMAGES = False
IMAGE_EXT = ('.jpg', '.jpeg', '.png', '.webp', '.bmp')
MIN_SIDE = 96          # smaller images carry too little detail for a 224x224 model
MAX_ASPECT = 4.0       # banners / strips are not photos of a dish
NEAR_DUP_BITS = 3      # dHash (64 bit) Hamming distance treated as "the same picture"


def find_class_folders(src):
    """Every folder that directly contains images is a class folder named after the folder."""
    found = defaultdict(list)
    for dirpath, _, files in os.walk(src):
        if any(f.lower().endswith(IMAGE_EXT) for f in files):
            found[os.path.basename(dirpath)].append(dirpath)
    return found


def resolve(folder_name):
    key = normalise(folder_name)
    return FOOD101.get(key) or SYNONYMS.get(key)


def load_official_test_ids(src):
    """Food-101 ships meta/meta/test.txt with lines like `apple_pie/1011328`. Returns a set or None."""
    for dirpath, _, files in os.walk(src):
        if 'test.txt' in files and 'train.txt' in files:
            with open(os.path.join(dirpath, 'test.txt')) as fh:
                ids = {line.strip() for line in fh if line.strip()}
            if ids:
                return ids
    return None


def dhash(img, size=8):
    g = img.convert('L').resize((size + 1, size), Image.LANCZOS)
    px = list(g.getdata())
    bits = 0
    for row in range(size):
        for col in range(size):
            bits = (bits << 1) | (px[row * (size + 1) + col] > px[row * (size + 1) + col + 1])
    return bits


def hamming(a, b):
    return bin(a ^ b).count('1')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True)
    ap.add_argument('--out', default='clean')
    ap.add_argument('--max-train', type=int, default=600, help='training images kept per class')
    ap.add_argument('--max-side', type=int, default=384)
    ap.add_argument('--val-fraction', type=float, default=0.15, help='only used when there is no official split')
    ap.add_argument('--seed', type=int, default=7)
    args = ap.parse_args()
    random.seed(args.seed)

    classes = find_class_folders(args.src)
    mapped = {name: resolve(name) for name in classes}
    used = {n: t for n, t in mapped.items() if t}
    skipped = sorted(n for n, t in mapped.items() if not t)
    official_test = load_official_test_ids(args.src)
    # If the folder was pre-filtered (only some classes extracted), classes.txt still lists them all.
    not_extracted = []
    for dirpath, _, files in os.walk(args.src):
        if 'classes.txt' in files:
            with open(os.path.join(dirpath, 'classes.txt')) as fh:
                listed = [l.strip() for l in fh if l.strip()]
            not_extracted = sorted(set(listed) - set(classes))
            break
    print(f'{len(classes)} class folders found; {len(used)} map to catalogue foods; {len(skipped)} skipped')
    print('official train/test split found:', bool(official_test))
    if not used:
        raise SystemExit('No class matched a catalogue food. Check class_map.py or the dataset layout.')

    issues = Counter()
    records = []  # dicts
    seen_md5 = {}
    scanned = Counter()

    for name, target in sorted(used.items()):
        for folder in classes[name]:
            for fn in sorted(os.listdir(folder)):
                if not fn.lower().endswith(IMAGE_EXT):
                    continue
                path = os.path.join(folder, fn)
                scanned[target] += 1
                try:
                    with Image.open(path) as im:
                        im.verify()
                    with Image.open(path) as im:
                        im.load()
                        w, h = im.size
                        if min(w, h) < MIN_SIDE:
                            issues['too small'] += 1
                            continue
                        if max(w, h) / min(w, h) > MAX_ASPECT:
                            issues['extreme aspect ratio'] += 1
                            continue
                        dh = dhash(im)
                except Exception:
                    issues['corrupt or unreadable'] += 1
                    continue
                with open(path, 'rb') as fh:
                    md5 = hashlib.md5(fh.read()).hexdigest()
                if md5 in seen_md5:
                    issues['exact duplicate'] += 1
                    continue
                seen_md5[md5] = path
                key = f'{name}/{os.path.splitext(fn)[0]}'
                split = None
                if official_test is not None:
                    split = 'val' if key in official_test else 'train'
                records.append({'target': target, 'cls': name, 'path': path, 'md5': md5, 'dh': dh, 'split': split})

    print('valid images before near-duplicate removal:', len(records))

    # ---- near-duplicates (perceptual hash). Bucket on two different 16-bit slices to avoid O(n^2)
    pairs = set()
    for shift in (48, 0):
        buckets = defaultdict(list)
        for i, r in enumerate(records):
            buckets[(r['dh'] >> shift) & 0xFFFF].append(i)
        for idxs in buckets.values():
            for a in range(len(idxs)):
                for b in range(a + 1, len(idxs)):
                    i, j = idxs[a], idxs[b]
                    if hamming(records[i]['dh'], records[j]['dh']) <= NEAR_DUP_BITS:
                        pairs.add((i, j))
    drop = set()
    cross_class = set()
    leak = 0
    for i, j in sorted(pairs):
        ri, rj = records[i], records[j]
        if ri['target'] != rj['target']:
            cross_class.update([i, j])
            continue
        if i in drop or j in drop:
            continue
        if official_test is not None and ri['split'] != rj['split']:
            drop.add(i if ri['split'] == 'train' else j)  # keep the validation copy, drop the training copy
            leak += 1
        else:
            drop.add(j)
            issues['near-duplicate in same class'] += 1
    if leak:
        issues['training image is a near-copy of a validation image (leak)'] += leak
    both = cross_class - drop
    if both:
        issues['near-identical across different classes (both dropped)'] += len(both)
    drop |= cross_class
    kept = [r for i, r in enumerate(records) if i not in drop]
    print('after duplicate removal:', len(kept))

    # ---- split, cap, resize, write
    by_class = defaultdict(list)
    for r in kept:
        by_class[r['target']].append(r)
    out_images = os.path.join(args.out, 'images')
    os.makedirs(out_images, exist_ok=True)
    rows, per_class = [], {}
    over_cap = 0
    for target, items in sorted(by_class.items()):
        random.shuffle(items)
        if official_test is not None:
            val = [r for r in items if r['split'] == 'val']
            train = [r for r in items if r['split'] == 'train']
        else:
            n_val = max(1, int(round(len(items) * args.val_fraction)))
            val, train = items[:n_val], items[n_val:]
        over_cap += max(0, len(train) - args.max_train)
        train = train[:args.max_train]
        os.makedirs(os.path.join(out_images, target), exist_ok=True)
        k = 0
        for split_name, group in (('val', val), ('train', train)):
            for r in group:
                with Image.open(r['path']) as im:
                    im = im.convert('RGB')
                    im.thumbnail((args.max_side, args.max_side), Image.LANCZOS)
                    rel = f'images/{target}/{k:04d}.jpg'
                    im.save(os.path.join(args.out, rel), 'JPEG', quality=90, optimize=True)
                rows.append((rel, target, split_name, r['cls'], r['md5']))
                k += 1
        per_class[target] = {'train': len(train), 'val': len(val), 'sources': sorted({r['cls'] for r in train + val})}

    with open(os.path.join(args.out, 'split.csv'), 'w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['path', 'label', 'split', 'source_class', 'md5'])
        w.writerows(rows)
    labels = sorted(per_class)
    with open(os.path.join(args.out, 'labels.json'), 'w') as fh:
        json.dump({'labels': labels, 'classes': per_class, 'official_split': official_test is not None}, fh, indent=1)

    # ---- report
    total_in = sum(scanned.values())
    n_out = len(rows)
    n_train = sum(v['train'] for v in per_class.values())
    n_val = sum(v['val'] for v in per_class.values())
    thin = [c for c, v in per_class.items() if v['train'] + v['val'] < 100]
    lines = [
        '# Food image dataset — cleaning report', '',
        f'Source: `{os.path.basename(os.path.normpath(args.src))}` — {len(classes)} class folders, '
        f'{len(used)} map to foods in the Baymax catalogue ({total_in} images in those folders).', '',
        f'**Result: {n_out} cleaned images in {len(labels)} classes — {n_train} train / {n_val} validation** '
        f'(training capped at {args.max_train} per class, longest side {args.max_side} px).', '',
        ('Split: the dataset\'s **official** split is used — its test images (manually cleaned by the dataset authors) are the validation set; '
         'the official training images are known to contain some noise (wrong labels, over-saturated photos).'
         if official_test is not None else f'Split: fixed random {int((1 - args.val_fraction) * 100)}/{int(args.val_fraction * 100)} split.'), '',
        '## Removed', '', '| Problem | Images |', '|---|---:|',
        *[f'| {k} | {v} |' for k, v in sorted(issues.items(), key=lambda kv: -kv[1])],
        f'| training images over the per-class cap (random subset kept) | {over_cap} |', '',
        '## Classes kept', '', '| Catalogue food | Train | Validation | Source folders |', '|---|---:|---:|---|',
        *[f"| {c} | {v['train']} | {v['val']} | {', '.join(v['sources'])} |" for c, v in sorted(per_class.items())], '',
        ('**Warning:** these classes have fewer than 100 images: ' + ', '.join(thin) + '.') if thin else 'Every kept class has at least 100 images.', '',
        '## Dishes not used (no matching food in the catalogue)', '',
        (f'The dataset has {len(classes) + len(not_extracted)} dishes. Only the {len(classes)} that map to catalogue foods were extracted and cleaned. '
         f'Not used ({len(not_extracted)}): ' + ', '.join(not_extracted) + '.') if not_extracted else
        (f'{len(skipped)} class folders: ' + (', '.join(skipped[:120]) + (' …' if len(skipped) > 120 else ''))), '',
        'To recognise more dishes, add the food to `assets/data/foods.json`, map the class in `class_map.py`, and re-run. '
        'Dishes the catalogue lacks that datasets commonly contain: ' + ', '.join(SUGGESTED_NEW_FOODS) + '.', '',
        '## Label noise you should know about', '',
        'Duplicate checks cannot find wrongly labelled photos. Food-101\'s authors state that the training images contain some noise (wrong labels, '
        'over-saturated pictures), and a visual check confirms it: e.g. naan or onion rings among "chicken curry" / "french fries" training images, and '
        'pita chips with no hummus. The validation images are the authors\' manually cleaned test set, so validation accuracy is trustworthy even though '
        'training labels are imperfect. After a first training run, review training images the model confidently assigns to a different class.', '',
        '## Limits', '',
        '* Food-101 is mostly Western dishes. Pakistani dishes (biryani, karahi, nihari, haleem, daal…) are NOT in it; add your own photos in a folder named with the catalogue id.',
        '* Several classes are merged because the catalogue has one entry for them (pasta from three dishes, cake from three).',
        '* The model recognises the dish, not the portion size; calories are for a standard serving.',
    ]
    with open(os.path.join(args.out, 'cleaning_report.md'), 'w') as fh:
        fh.write('\n'.join(lines) + '\n')

    print(f'wrote {n_out} images, {len(labels)} classes ({n_train} train / {n_val} val) -> {args.out}')
    for k, v in sorted(issues.items(), key=lambda kv: -kv[1]):
        print(f'  removed {v:5d}  {k}')


if __name__ == '__main__':
    main()
