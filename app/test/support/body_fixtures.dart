import 'dart:math' as math;

import 'package:app/services/posture/pose_landmark.dart';

/// Whole-body synthetic poses with a consistent joint chain, for form-check tests. Both body sides get the same
/// coordinates unless stated. Image coordinates: x to the right, y downwards. These test the evaluation logic; they are
/// not evidence of MediaPipe accuracy on real people.

typedef _P = math.Point<double>;

_P _rot(_P v, double deg) {
  final r = deg * math.pi / 180;
  return _P(v.x * math.cos(r) - v.y * math.sin(r), v.x * math.sin(r) + v.y * math.cos(r));
}

_P _add(_P a, _P v, double len) => _P(a.x + v.x * len, a.y + v.y * len);
_P _neg(_P v) => _P(-v.x, -v.y);

PoseFrame _frame(Map<List<int>, _P> parts, int t, {double visibility = 0.95}) {
  final points = List<PoseLandmark>.filled(PoseIndex.count, PoseLandmark(0.5, 0.05, 0, visibility));
  for (final MapEntry(key: ids, value: p) in parts.entries) {
    for (final i in ids) {
      points[i] = PoseLandmark(p.x, p.y, 0, visibility);
    }
  }
  return PoseFrame(landmarks: points, timestampMs: t);
}

/// Side view. [lean]: torso from vertical (0 upright, 90 horizontal). [hip]: shoulder–hip–knee angle (180 standing).
/// [knee]: hip–knee–ankle angle. [arm]: hip–shoulder–elbow angle (0 arm along the torso). [elbow]: shoulder–elbow–wrist.
PoseFrame sideBody(int t, {double lean = 0, double hip = 180, double knee = 180, double arm = 5, double elbow = 170}) {
  const h = _P(0.5, 0.55);
  final up = _P(math.sin(lean * math.pi / 180), -math.cos(lean * math.pi / 180));
  final s = _add(h, up, 0.25);
  final thigh = _rot(up, hip);
  final k = _add(h, thigh, 0.22);
  final shank = _rot(_neg(thigh), -knee);
  final a = _add(k, shank, 0.22);
  final upperArm = _rot(_neg(up), -arm);
  final e = _add(s, upperArm, 0.17);
  final fore = _rot(_neg(upperArm), elbow);
  final w = _add(e, fore, 0.15);
  return _frame({
    [PoseIndex.leftShoulder, PoseIndex.rightShoulder]: s,
    [PoseIndex.leftHip, PoseIndex.rightHip]: h,
    [PoseIndex.leftKnee, PoseIndex.rightKnee]: k,
    [PoseIndex.leftAnkle, PoseIndex.rightAnkle]: a,
    [PoseIndex.leftElbow, PoseIndex.rightElbow]: e,
    [PoseIndex.leftWrist, PoseIndex.rightWrist]: w,
  }, t);
}

/// Front view (facing the camera). [arms]: hip–shoulder–elbow angle of each arm (straight arms).
/// [feet]: ankle separation ÷ hip width. [armDifference] raises the right arm more than the left.
PoseFrame frontBody(int t, {double arms = 20, double feet = 1.0, double armDifference = 0, double elbow = 175}) {
  const ls = _P(0.40, 0.30), rs = _P(0.60, 0.30), lh = _P(0.44, 0.55), rh = _P(0.56, 0.55);
  _P arm(_P shoulder, double angle, double side) {
    // down = (0,1); rotate outwards (side −1 = to the left) by [angle]
    final r = angle * math.pi / 180;
    return _P(side * math.sin(r), math.cos(r));
  }

  final la = arm(ls, arms, -1), ra = arm(rs, arms + armDifference, 1);
  final le = _add(ls, la, 0.17), re = _add(rs, ra, 0.17);
  final lw = _add(le, _rot(la, -(180 - elbow)), 0.15), rw = _add(re, _rot(ra, 180 - elbow), 0.15);
  final half = 0.12 * feet / 2;
  final lAnkle = _P(0.5 - half, 0.95), rAnkle = _P(0.5 + half, 0.95);
  return _frame({
    [PoseIndex.leftShoulder]: ls,
    [PoseIndex.rightShoulder]: rs,
    [PoseIndex.leftHip]: lh,
    [PoseIndex.rightHip]: rh,
    [PoseIndex.leftElbow]: le,
    [PoseIndex.rightElbow]: re,
    [PoseIndex.leftWrist]: lw,
    [PoseIndex.rightWrist]: rw,
    [PoseIndex.leftKnee]: _P((lh.x + lAnkle.x) / 2, 0.75),
    [PoseIndex.rightKnee]: _P((rh.x + rAnkle.x) / 2, 0.75),
    [PoseIndex.leftAnkle]: lAnkle,
    [PoseIndex.rightAnkle]: rAnkle,
  }, t);
}

/// Plank / push-up seen from the side: shoulders left, ankles right. [hipOffset] moves the hips up (+) or down (−)
/// as a fraction of the shoulder–ankle distance. [elbow]: shoulder–elbow–wrist angle (arms under the shoulders).
PoseFrame plankBody(int t, {double hipOffset = 0, double elbow = 170}) {
  const s = _P(0.25, 0.50), a = _P(0.85, 0.50);
  final length = a.x - s.x;
  final h = _P(0.55, 0.50 - hipOffset * length);
  final k = _P((h.x + a.x) / 2, (h.y + a.y) / 2);
  const e = _P(0.25, 0.65);
  final fore = _rot(const _P(0, -1), elbow); // from elbow: up rotated by the elbow angle
  final w = _add(e, fore, 0.15);
  return _frame({
    [PoseIndex.leftShoulder, PoseIndex.rightShoulder]: s,
    [PoseIndex.leftHip, PoseIndex.rightHip]: h,
    [PoseIndex.leftKnee, PoseIndex.rightKnee]: k,
    [PoseIndex.leftAnkle, PoseIndex.rightAnkle]: a,
    [PoseIndex.leftElbow, PoseIndex.rightElbow]: e,
    [PoseIndex.leftWrist, PoseIndex.rightWrist]: w,
  }, t);
}

/// Frames at ~30 FPS while [value] goes from [from] to [to] over [ms].
List<PoseFrame> sweep(PoseFrame Function(int t, double v) build, double from, double to, int ms, {int startMs = 0}) => [
      for (var i = 1; i <= math.max(1, ms ~/ 33); i++) build(startMs + i * 33, from + (to - from) * i / math.max(1, ms ~/ 33)),
    ];
