// On-device validation of posture evaluation on REAL people: the free-exercise-db photos.
//
//   flutter test integration_test/dataset_pose_validation_test.dart -d <device-id> > results.log
//
// free-exercise-db (the project's exercise dataset, Unlicense) has two photographs of a person for most exercises:
// the start and the end position. For every camera-tracked exercise the plan can schedule, this test downloads both
// photos ON THE PHONE, runs them through the production MediaPipe model and the production posture engine, and logs
// one JSON line per exercise ("[val] {...}"):
//   * detected     — MediaPipe found a person in each photo;
//   * measurable   — the landmarks the tracker needs were visible;
//   * span         — one photo is at the rest position and the other past the turning point (a rep is countable);
//   * repCounted   — the real engine counted exactly one rep when the person moved rest → end → rest;
//   * falseAlarms  — form checks that fired on the demonstrated (correct) form.
// Nothing is stored on the phone; images are processed in memory.
//
// LIMITS: static photos, not live movement — this cannot measure fault detection (sensitivity) or tracking at speed.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app/models/plan.dart';
import 'package:app/models/workout_readiness.dart';
import 'package:app/services/exercise_catalog.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/exercise_repository.dart';
import 'package:app/services/posture/exercise_form_rules.dart';
import 'package:app/services/posture/hold_tracker.dart';
import 'package:app/services/posture/movement_patterns.dart';
import 'package:app/services/posture/pose_estimator.dart';
import 'package:app/services/posture/pose_landmark.dart';
import 'package:app/services/posture/posture_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// RGBA → NV21 (full-range BT.601), the format the camera delivers.
Uint8List _nv21(Uint8List rgba, int w, int h) {
  final out = Uint8List(w * h * 3 ~/ 2);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      out[y * w + x] = (0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2]).round().clamp(0, 255);
    }
  }
  var o = w * h;
  for (var y = 0; y < h; y += 2) {
    for (var x = 0; x < w; x += 2) {
      final i = (y * w + x) * 4;
      final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
      out[o++] = (0.5 * r - 0.4187 * g - 0.0813 * b + 128).round().clamp(0, 255); // V
      out[o++] = (-0.1687 * r - 0.3313 * g + 0.5 * b + 128).round().clamp(0, 255); // U
    }
  }
  return out;
}

Future<Uint8List?> _download(HttpClient http, String url) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final req = await http.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final bytes = BytesBuilder();
      await for (final chunk in res) {
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } catch (_) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('posture evaluation on real exercise photos (free-exercise-db)', (tester) async {
    await tester.runAsync(() async {
      ExerciseLibrary.loadFromJsonString(await rootBundle.loadString('assets/data/exercises.json'));
      ExerciseCatalog.loadFromJsonString(await rootBundle.loadString(ExerciseCatalog.asset));
      final eligible = <Exercise>[
        ...ExerciseLibrary.all,
        ...ExerciseCatalog.plannableWith(WorkoutReadiness.equipmentOptions.keys.toSet())
            .where((e) => e.level <= 2 && !e.tags.contains('maximal')),
      ];
      final estimator = MediaPipePoseEstimator();
      await estimator.initialize();
      final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      var t = 0;

      Future<PoseFrame?> pose(String url) async {
        final bytes = await _download(http, url);
        if (bytes == null) return null;
        final codec = await ui.instantiateImageCodec(bytes);
        final image = (await codec.getNextFrame()).image;
        final w = image.width & ~1, h = image.height & ~1;
        final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
        // crop to even size, row by row
        final rgba = Uint8List(w * h * 4);
        for (var y = 0; y < h; y++) {
          rgba.setRange(y * w * 4, (y + 1) * w * 4, data, y * image.width * 4);
        }
        final nv21 = _nv21(rgba, w, h);
        PoseFrame? last;
        // Video-mode tracking: give each photo a few frames so detection settles on it.
        for (var i = 0; i < 4; i++) {
          t += 100;
          last = await estimator.estimate(CameraFrame(planes: [FramePlane(nv21, w, 1)], width: w, height: h, rotationDegrees: 0, timestampMs: t));
        }
        return last;
      }

      var done = 0;
      for (final e in eligible) {
        final posture = ExerciseRepository.postureFor(e);
        final cfg = posture.form;
        final urls = ExerciseCatalog.imagesFor(e);
        if (cfg == null || urls.length < 2) continue;
        final f0 = await pose(urls[0]);
        final f1 = await pose(urls[1]);
        final result = <String, Object?>{
          'id': e.id,
          'name': e.name,
          'pattern': posture.movementPattern.name,
          'level': posture.level.name,
          'detected': [f0?.hasPose ?? false, f1?.hasPose ?? false],
        };
        final m0 = f0 == null ? null : PoseAnalyzer.measure(f0, cfg);
        final m1 = f1 == null ? null : PoseAnalyzer.measure(f1, cfg);
        result['measurable'] = [m0 != null, m1 != null];
        if (m0 != null && m1 != null) {
          final a0 = m0.primaryAngle, a1 = m1.primaryAngle;
          result['angles'] = [a0.round(), a1.round()];
          if (cfg.kind == TrackingKind.hold) {
            final tracker = HoldTracker(cfg);
            final inPosition = [tracker.matches(m0), tracker.matches(m1)];
            result['inPosition'] = inPosition;
            result['falseAlarms'] = [
              for (final (m, ok) in [(m0, inPosition[0]), (m1, inPosition[1])])
                if (ok)
                  for (final c in cfg.checks)
                    if (c.evaluate(m) == CheckOutcome.fail) c.id,
            ];
          } else {
            bool atRest(double a) => cfg.opening ? a <= cfg.extendedAngle : a >= cfg.extendedAngle;
            bool pastTurn(double a) => cfg.opening ? a >= cfg.flexedAngle : a <= cfg.flexedAngle;
            final restFirst = atRest(a0) && pastTurn(a1);
            final restSecond = atRest(a1) && pastTurn(a0);
            result['span'] = restFirst || restSecond;
            final restFrame = restSecond ? f1! : f0!;
            final turnFrame = restSecond ? f0! : f1!;
            final mRest = restSecond ? m1 : m0;
            final mTurn = restSecond ? m0 : m1;
            // Real engine, real landmarks: rest → end position → rest, 10 frames each at 100 ms.
            final engine = PostureEngine(cfg);
            var ts = 0;
            for (final frame in [...List.filled(10, restFrame), ...List.filled(10, turnFrame), ...List.filled(10, restFrame)]) {
              ts += 100;
              engine.process(PoseFrame(landmarks: frame.landmarks, worldLandmarks: frame.worldLandmarks, timestampMs: ts, aspectRatio: frame.aspectRatio));
            }
            result['repCounted'] = engine.reps == 1;
            // Checks on the demonstrated (correct) form; sway = lean change between the two photos.
            final lean0 = mRest.torsoLean, lean1 = mTurn.torsoLean;
            final sway = lean0 != null && lean1 != null ? (lean1 - lean0).abs() : null;
            final turnCtx = mTurn.withContext(torsoSway: sway, atPeak: true);
            final restCtx = mRest.withContext(torsoSway: 0);
            result['falseAlarms'] = {
              for (final c in cfg.checks)
                if (c.evaluate(turnCtx) == CheckOutcome.fail || c.evaluate(restCtx) == CheckOutcome.fail) c.id,
            }.toList();
            result['notApplicable'] = [
              for (final c in cfg.checks)
                if (c.evaluate(turnCtx) == CheckOutcome.notApplicable && c.evaluate(restCtx) == CheckOutcome.notApplicable) c.id,
            ];
          }
        }
        // Raw landmarks (rounded) so the result can be replayed off-device by test/real_pose_replay_test.dart.
        List<List<double>> pack(List<PoseLandmark> l) => [
              for (final p in l)
                [double.parse(p.x.toStringAsFixed(4)), double.parse(p.y.toStringAsFixed(4)), double.parse(p.z.toStringAsFixed(4)), double.parse(p.visibility.toStringAsFixed(3))]
            ];
        result['frames'] = [
          for (final f in [f0, f1])
            if (f != null && f.hasPose) {'lm': pack(f.landmarks), 'world': pack(f.worldLandmarks), 'aspect': f.aspectRatio} else null,
        ];
        // ignore: avoid_print
        print('[val] ${jsonEncode(result)}');
        done++;
      }
      http.close();
      await estimator.dispose();
      // ignore: avoid_print
      print('[val-done] $done');
      expect(done, greaterThan(0));
    });
  }, timeout: const Timeout(Duration(minutes: 60)));
}
