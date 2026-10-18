import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:app/models/plan.dart';
import 'package:app/models/workout_readiness.dart';
import 'package:app/services/exercise_catalog.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/widgets/exercise_visual.dart';
import 'package:app/widgets/pose_illustration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every exercise the plan can schedule has a start/end picture: its own photos, a similar exercise's photos (labelled),
/// or a drawn illustration.
///
///   BAYMAX_RENDER_ILLUSTRATIONS=1 flutter test test/exercise_visual_test.dart   → build/illustrations.png (review sheet)
void main() {
  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    ExerciseCatalog.loadFromJsonString(File('assets/data/exercise_catalog.json').readAsStringSync());
  });

  List<Exercise> schedulable() => [
        ...ExerciseLibrary.all,
        ...ExerciseCatalog.plannableWith(WorkoutReadiness.equipmentOptions.keys.toSet())
            .where((e) => e.level <= 2 && !e.tags.contains('maximal')),
      ];

  test('every schedulable exercise has a start/end picture, with an honest caption', () {
    final missing = [for (final e in schedulable()) if (ExerciseVisualInfo.of(e).kind == VisualKind.none) e.id];
    expect(missing, isEmpty);
    for (final e in ExerciseLibrary.all) {
      final v = ExerciseVisualInfo.of(e);
      if (v.kind == VisualKind.similarPhotos) {
        expect(v.caption, contains('similar exercise'), reason: e.id);
        expect(v.urls.length, greaterThanOrEqualTo(2), reason: '${e.id}: start and end');
      }
      if (v.kind == VisualKind.illustration) expect(v.caption, contains('Illustration'), reason: e.id);
    }
    expect(ExerciseVisualInfo.of(ExerciseLibrary.byId('squat')!).kind, VisualKind.photos);
    expect(ExerciseVisualInfo.of(ExerciseLibrary.byId('incline_pushup')!).kind, VisualKind.similarPhotos);
    expect(ExerciseVisualInfo.of(ExerciseLibrary.byId('jumping_jacks')!).kind, VisualKind.illustration);
  });

  test('illustrated figures stay inside the picture and on or above the floor', () {
    Offset dir(double d) => Offset(math.sin(d * math.pi / 180), -math.cos(d * math.pi / 180));
    for (final entry in PoseIllustrations.specs.entries) {
      for (final pose in [entry.value.start, entry.value.end]) {
        final shoulder = pose.hip + dir(pose.torso) * 0.26;
        final points = <Offset>[pose.hip, shoulder];
        for (final (from, limb, a, b) in [
          (shoulder, pose.armNear, 0.16, 0.15),
          (shoulder, pose.armFar, 0.16, 0.15),
          (pose.hip, pose.legNear, 0.22, 0.22),
          (pose.hip, pose.legFar, 0.22, 0.22),
        ]) {
          final mid = from + dir(limb[0]) * a;
          points.addAll([mid, mid + dir(limb[1]) * b]);
        }
        for (final p in points) {
          expect(p.dx, inInclusiveRange(-0.02, 1.02), reason: '${entry.key} x');
          expect(p.dy, inInclusiveRange(-0.08, 0.99), reason: '${entry.key}: inside the picture, not through the floor');
        }
      }
    }
  });

  testWidgets('render the illustration review sheet', (tester) async {
    if (Platform.environment['BAYMAX_RENDER_ILLUSTRATIONS'] != '1') return;
    final key = GlobalKey();
    final specs = PoseIllustrations.specs.entries.toList();
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: Container(
          color: Colors.white,
          child: Wrap(children: [
            for (final e in specs)
              for (final pose in [e.value.start, e.value.end])
                SizedBox(
                  width: 300,
                  height: 170,
                  child: Column(children: [
                    Text(e.key, style: const TextStyle(fontSize: 11)),
                    Expanded(
                      child: PoseIllustration(
                          spec: PoseIllustrationSpec(pose, pose, front: e.value.front, props: e.value.props), height: 150, animate: false),
                    ),
                  ]),
                ),
          ]),
        ),
      ),
    ));
    await tester.pump();
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build').createSync(recursive: true);
      File('build/illustrations.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
