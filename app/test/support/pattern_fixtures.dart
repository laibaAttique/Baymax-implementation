import 'dart:async';
import 'dart:math' as math;

import 'package:app/services/posture/exercise_form_rules.dart';
import 'package:app/services/posture/pose_landmark.dart';
import 'package:app/services/posture/pose_stream.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Synthetic poses for any tracker configuration: the rep-driving joint of [config] is placed at exactly [angle], on
/// both body sides, so the engine runs through the same landmark → angle path as on a device.
///
/// [baseDeg] turns the first segment (vertex → a) away from straight up, e.g. 90 puts the shoulder level with the hip
/// for a plank. [hidden] landmarks get zero visibility.
PoseFrame jointFrame(ExerciseFormConfig config, double angle, int timestampMs,
    {double baseDeg = 0, Set<int> hidden = const {}, double visibility = 0.95}) {
  const vertex = math.Point<double>(0.5, 0.5);
  final b = baseDeg * math.pi / 180;
  final c = (baseDeg + angle) * math.pi / 180;
  final a = math.Point<double>(vertex.x + 0.2 * math.sin(b), vertex.y - 0.2 * math.cos(b));
  final end = math.Point<double>(vertex.x + 0.2 * math.sin(c), vertex.y - 0.2 * math.cos(c));

  final points = List<PoseLandmark>.filled(PoseIndex.count, PoseLandmark(0.5, 0.2, 0, visibility));
  void put(int i, math.Point<double> p) => points[i] = PoseLandmark(p.x, p.y, 0, visibility);
  for (final t in [config.leftPrimary, config.rightPrimary]) {
    put(t.a, a);
    put(t.vertex, vertex);
    put(t.c, end);
  }
  // Give the torso a real direction when the triple does not include both shoulder and hip (upright by default).
  final usesTorso = {config.leftPrimary.a, config.leftPrimary.vertex, config.leftPrimary.c}
      .containsAll({PoseIndex.leftShoulder, PoseIndex.leftHip});
  if (!usesTorso) {
    final hipL = points[PoseIndex.leftHip];
    final hip = math.Point<double>(hipL.x, hipL.y);
    final shoulder = math.Point<double>(hip.x, hip.y - 0.25);
    if (!{config.leftPrimary.a, config.leftPrimary.vertex, config.leftPrimary.c}.contains(PoseIndex.leftShoulder)) {
      put(PoseIndex.leftShoulder, shoulder);
      put(PoseIndex.rightShoulder, shoulder);
    }
  }
  for (final i in hidden) {
    points[i] = PoseLandmark(points[i].x, points[i].y, 0, 0);
  }
  return PoseFrame(landmarks: points, timestampMs: timestampMs);
}

/// Frames at ~30 FPS moving the joint linearly between angles.
class JointMotion {
  final ExerciseFormConfig config;
  final double baseDeg;
  final List<PoseFrame> frames = [];
  int _t;
  double _angle;

  JointMotion(this.config, {required double startAngle, int startMs = 0, this.baseDeg = 0})
      : _t = startMs,
        _angle = startAngle;

  int get nowMs => _t;

  JointMotion moveTo(double angle, int ms) {
    final steps = math.max(1, ms ~/ 33);
    final from = _angle;
    for (var i = 1; i <= steps; i++) {
      _t += 33;
      frames.add(jointFrame(config, from + (angle - from) * i / steps, _t, baseDeg: baseDeg));
    }
    _angle = angle;
    return this;
  }

  JointMotion hold(int ms) => moveTo(_angle, ms);
}

/// Camera + pose model stand-in for screen tests: frames are pushed by hand.
class ScriptedPoseStream implements PoseStream {
  final StreamController<PoseFrame> controller = StreamController<PoseFrame>.broadcast();
  final ValueNotifier<double> rate = ValueNotifier<double>(0);
  bool running = false;

  @override
  Future<void> start() async => running = true;
  @override
  Future<void> stop() async => running = false;
  @override
  Stream<PoseFrame> get frames => controller.stream;
  @override
  Widget? buildPreview() => running ? const ColoredBox(color: Colors.black) : null;
  @override
  double get previewAspectRatio => 3 / 4;
  @override
  bool get mirrored => true;
  @override
  bool get canSwitchCamera => false;
  @override
  Future<void> switchCamera() async {}
  @override
  ValueListenable<double> get fps => rate;
  @override
  double? get averageFps => 15;
}
