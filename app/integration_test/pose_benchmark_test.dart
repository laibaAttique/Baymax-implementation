// On-device benchmark of the posture pipeline (report NFR-P4: ≥ 15 FPS).
//
//   flutter test integration_test/pose_benchmark_test.dart -d <device-id>
//
// Part 1 times the native MediaPipe bridge with synthetic camera frames.
// Part 2 runs the real camera stream for a few seconds and reports the rate
// at which frames are analysed. Frames are processed in memory only; nothing
// is saved. With nobody in view the model runs its slower "search" path on
// every frame, so these numbers are a lower bound for a tracked person.

import 'dart:typed_data';

import 'package:app/services/posture/pose_estimator.dart';
import 'package:app/services/posture/pose_landmark.dart';
import 'package:app/services/posture/pose_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

String _stats(String label, List<num> values) {
  if (values.isEmpty) return '$label: no data';
  final sorted = [...values]..sort();
  final mean = values.fold<double>(0, (a, b) => a + b) / values.length;
  num pct(double p) => sorted[((sorted.length - 1) * p).round()];
  return '$label: mean ${mean.toStringAsFixed(1)}  median ${pct(0.5)}  p90 ${pct(0.9)}  (n=${values.length})';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MediaPipe bridge with synthetic frames', (tester) async {
    final estimator = MediaPipePoseEstimator();
    await estimator.initialize();
    const width = 720, height = 480;
    final nv21 = Uint8List(width * height * 3 ~/ 2)
      ..fillRange(0, width * height, 110)
      ..fillRange(width * height, width * height * 3 ~/ 2, 128);

    final roundTrip = <int>[], inference = <int>[], convert = <int>[];
    final clock = Stopwatch()..start();
    for (var i = 0; i < 45; i++) {
      final started = clock.elapsedMilliseconds;
      final PoseFrame result = await estimator.estimate(CameraFrame(
        planes: [FramePlane(nv21, width, 1)],
        width: width,
        height: height,
        rotationDegrees: 270,
        timestampMs: started,
      ));
      if (i < 5) continue; // warm-up
      roundTrip.add(clock.elapsedMilliseconds - started);
      if (result.inferenceMs != null) inference.add(result.inferenceMs!);
      if (result.convertMs != null) convert.add(result.convertMs!);
    }
    await estimator.dispose();

    debugPrint('[bench] ${_stats('bridge round trip ms', roundTrip)}');
    debugPrint('[bench] ${_stats('model inference ms', inference)}');
    debugPrint('[bench] ${_stats('frame conversion ms', convert)}');
    expect(roundTrip, isNotEmpty);
  });

  testWidgets('Live camera stream', (tester) async {
    final stream = CameraPoseStream();
    final inference = <int>[], convert = <int>[];
    var analysed = 0, withPose = 0;
    await stream.start();
    final sub = stream.frames.listen((f) {
      analysed++;
      if (f.hasPose) withPose++;
      if (f.inferenceMs != null) inference.add(f.inferenceMs!);
      if (f.convertMs != null) convert.add(f.convertMs!);
    });
    final watch = Stopwatch()..start();
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 12)));
    final seconds = watch.elapsedMilliseconds / 1000;
    final cameraFrames = stream.cameraFrames;
    await sub.cancel();
    await stream.stop();

    debugPrint('[bench] camera delivered ${(cameraFrames / seconds).toStringAsFixed(1)} frames/s');
    debugPrint('[bench] analysed ${(analysed / seconds).toStringAsFixed(1)} frames/s '
        '(average reported by the stream: ${stream.averageFps?.toStringAsFixed(1)}), person found in $withPose of $analysed');
    debugPrint('[bench] ${_stats('live inference ms', inference)}');
    debugPrint('[bench] ${_stats('live conversion ms', convert)}');
    expect(analysed, greaterThan(0));
  });
}
