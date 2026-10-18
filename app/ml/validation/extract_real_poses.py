"""Extracts the real MediaPipe landmarks logged by integration_test/dataset_pose_validation_test.dart into the replay
fixture used by test/real_pose_replay_test.dart (runs on the PC, no phone needed).

  python ml/validation/extract_real_poses.py <device log> test/fixtures/real_poses.json

Source photos: free-exercise-db (Unlicense / public domain), pinned commit. Only landmark coordinates are kept, no images.
"""
import json
import sys

log, out = sys.argv[1], sys.argv[2]
rows = []
for line in open(log, encoding='utf-8', errors='replace'):
    i = line.find('[val] ')
    if i < 0:
        continue
    r = json.loads(line[i + 6:])
    frames = r.get('frames') or []
    if len(frames) == 2 and all(frames):
        rows.append({'id': r['id'], 'name': r['name'], 'pattern': r['pattern'], 'frames': frames})
json.dump({
    'source': 'free-exercise-db photos (Unlicense), commit f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5; '
              'landmarks from pose_landmarker_lite on a Redmi Note 11 (Android 13)',
    'exercises': rows,
}, open(out, 'w', encoding='utf-8'), separators=(',', ':'))
print(len(rows), 'exercises with landmarks for both photos')
