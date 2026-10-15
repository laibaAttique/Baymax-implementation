import 'dart:math' as math;

import 'package:app/models/workout_session.dart';
import 'package:app/services/posture/pose_landmark.dart';

/// Synthetic side-view poses for the posture tests. Geometry is built from the
/// requested joint angles, so the engine is exercised through the same
/// landmark → angle path as on a device.

const squatExercise = SessionExercise(
  id: 'squat',
  name: 'Bodyweight Squat',
  group: 'legs',
  muscles: ['Quadriceps', 'Glutes'],
  steps: ['Stand with feet shoulder-width apart.', 'Sit back and down.', 'Drive up through your heels.'],
  sets: 3,
  reps: 12,
  restSeconds: 30,
);

const plankExercise = SessionExercise(
  id: 'plank',
  name: 'Plank Hold',
  group: 'core',
  steps: ['Keep a straight line from head to heels.'],
  timed: true,
  sets: 2,
  seconds: 20,
  restSeconds: 10,
);

/// A standing/squatting person seen from the side. [kneeAngle] is the
/// hip–knee–ankle angle; [torsoLean] is the lean of the trunk from vertical.
PoseFrame squatFrame(
  double kneeAngle,
  int timestampMs, {
  double torsoLean = 10,
  double visibility = 0.95,
}) {
  const ankle = math.Point<double>(0.5, 0.9);
  const knee = math.Point<double>(0.5, 0.7);
  final k = kneeAngle * math.pi / 180;
  final hip = math.Point<double>(knee.x + 0.2 * math.sin(k), knee.y + 0.2 * math.cos(k));
  final l = torsoLean * math.pi / 180;
  final shoulder = math.Point<double>(hip.x + 0.25 * math.sin(l), hip.y - 0.25 * math.cos(l));

  final points = List<PoseLandmark>.filled(PoseIndex.count, PoseLandmark(0.5, 0.3, 0, visibility));
  void set(List<int> indices, math.Point<double> p) {
    for (final i in indices) {
      points[i] = PoseLandmark(p.x, p.y, 0, visibility);
    }
  }

  set([PoseIndex.leftAnkle, PoseIndex.rightAnkle], ankle);
  set([PoseIndex.leftKnee, PoseIndex.rightKnee], knee);
  set([PoseIndex.leftHip, PoseIndex.rightHip], hip);
  set([PoseIndex.leftShoulder, PoseIndex.rightShoulder], shoulder);
  return PoseFrame(landmarks: points, timestampMs: timestampMs);
}

/// Frame timestamps and knee angles for a movement, sampled at ~30 FPS.
class Motion {
  final List<PoseFrame> frames = [];
  int _t;
  double _angle;

  Motion({int startMs = 0, double startAngle = 172})
      : _t = startMs,
        _angle = startAngle;

  int get nowMs => _t;

  /// Stay at the current angle for [ms].
  Motion hold(int ms, {double torsoLean = 10}) => moveTo(_angle, ms, torsoLean: torsoLean);

  /// Move linearly to [angle] over [ms].
  Motion moveTo(double angle, int ms, {double torsoLean = 10}) {
    final steps = math.max(1, ms ~/ 33);
    final from = _angle;
    for (var i = 1; i <= steps; i++) {
      _t += 33;
      frames.add(squatFrame(from + (angle - from) * i / steps, _t, torsoLean: torsoLean));
    }
    _angle = angle;
    return this;
  }

  /// One full squat: down to [depth] and back up.
  Motion squat({double depth = 88, int downMs = 900, int upMs = 900, double torsoLean = 10}) {
    return moveTo(depth, downMs, torsoLean: torsoLean).hold(150, torsoLean: torsoLean).moveTo(172, upMs).hold(300);
  }
}
