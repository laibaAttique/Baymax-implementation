"""Runs the app's own pose model (assets/models/pose_landmarker_lite.task) on the free-exercise-db photos of every
camera-tracked exercise, on the PC, and writes "[val] {...}" lines in the same format as the on-device test
(integration_test/dataset_pose_validation_test.dart), so ml/validation/extract_real_poses.py can build the replay fixture.

  <venv>/python ml/validation/pc_pose_landmarks.py <image cache dir> <out log>

Needs the `mediapipe` Python package (Google, Apache-2.0). Images are cached locally only for this run's input; only
landmark coordinates are written out.
"""
import json
import os
import sys
import urllib.request

import mediapipe as mp
from mediapipe.tasks import python as mp_tasks
from mediapipe.tasks.python import vision

APP = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
cache, out = sys.argv[1], sys.argv[2]
os.makedirs(cache, exist_ok=True)

audit = json.load(open(os.path.join(APP, 'docs/review/camera_support_audit.json'), encoding='utf-8'))['exercises']
catalog = {e['id']: e for e in json.load(open(os.path.join(APP, 'assets/data/exercise_catalog.json'), encoding='utf-8'))['exercises']}
curated = {e['id']: e for e in json.load(open(os.path.join(APP, 'assets/data/exercises.json'), encoding='utf-8'))}


def image_urls(ex_id):
    if ex_id in catalog:
        return catalog[ex_id].get('imageUrls') or []
    c = curated.get(ex_id)
    if c and c.get('referenceMatch') == 'exact' and c.get('referenceId') in catalog:
        return catalog[c['referenceId']].get('imageUrls') or []
    return []


options = vision.PoseLandmarkerOptions(
    base_options=mp_tasks.BaseOptions(model_asset_path=os.path.join(APP, 'assets/models/pose_landmarker_lite.task')),
    running_mode=vision.RunningMode.IMAGE,
    num_poses=1,
)
landmarker = vision.PoseLandmarker.create_from_options(options)


def pack(lms):
    return [[round(p.x, 4), round(p.y, 4), round(p.z, 4), round(p.visibility if p.visibility is not None else 0, 3)] for p in lms]


done = 0
with open(out, 'w', encoding='utf-8') as log:
    for x in audit:
        if x['cameraSupport'] == 'Not reliably supported':
            continue
        urls = image_urls(x['id'])
        if len(urls) < 2:
            continue
        frames = []
        for url in urls[:2]:
            path = os.path.join(cache, url.split('/exercises/')[-1].replace('/', '__'))
            if not os.path.exists(path):
                try:
                    urllib.request.urlretrieve(url, path)
                except Exception:
                    frames.append(None)
                    continue
            image = mp.Image.create_from_file(path)
            res = landmarker.detect(image)
            if not res.pose_landmarks:
                frames.append(None)
                continue
            frames.append({'lm': pack(res.pose_landmarks[0]), 'world': pack(res.pose_world_landmarks[0]),
                           'aspect': image.width / image.height})
        log.write('[val] ' + json.dumps({'id': x['id'], 'name': x['name'], 'pattern': x['movementPattern'],
                                         'detected': [f is not None for f in frames], 'frames': frames}) + '\n')
        done += 1
        if done % 25 == 0:
            print(done, flush=True)
print('done', done)
