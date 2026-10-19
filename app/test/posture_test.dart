import 'package:app/models/workout_session.dart';
import 'package:app/services/posture/exercise_form_rules.dart';
import 'package:app/services/posture/pose_landmark.dart';
import 'package:app/services/posture/pose_math.dart';
import 'package:app/services/posture/posture_engine.dart';
import 'package:app/services/posture/rep_counter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pose_fixtures.dart';

PostureEngine _engine([String id = 'squat']) => PostureEngine(ExerciseFormRules.forExercise(id)!);

/// Runs [motion] through [engine] and returns every analysis.
List<PostureAnalysis> _run(PostureEngine engine, Motion motion) => [for (final f in motion.frames) engine.process(f)];

void main() {
  group('Joint angle', () {
    test('known angles', () {
      expect(PoseMath.jointAngle(const Vec3(1, 0), const Vec3(0, 0), const Vec3(0, 1)), closeTo(90, 1e-9));
      expect(PoseMath.jointAngle(const Vec3(-1, 0), const Vec3(0, 0), const Vec3(1, 0)), closeTo(180, 1e-9));
      expect(PoseMath.jointAngle(const Vec3(1, 0), const Vec3(0, 0), const Vec3(1, 1)), closeTo(45, 1e-9));
      expect(PoseMath.jointAngle(const Vec3(0, 0, 1), const Vec3(0, 0, 0), const Vec3(1, 0, 0)), closeTo(90, 1e-9));
    });

    test('stays in range for collinear points where rounding could exceed the acos domain', () {
      for (var i = 1; i < 200; i++) {
        final a = Vec3(i * 0.1, i * 0.3);
        final same = PoseMath.jointAngle(a, const Vec3(0, 0), Vec3(a.x * 7, a.y * 7));
        final opposite = PoseMath.jointAngle(a, const Vec3(0, 0), Vec3(-a.x * 3, -a.y * 3));
        expect(same, inInclusiveRange(0, 180));
        expect(same!.isNaN, isFalse);
        expect(opposite, closeTo(180, 1e-4));
      }
    });

    test('zero-length vectors and invalid coordinates give null, not NaN', () {
      expect(PoseMath.jointAngle(const Vec3(0, 0), const Vec3(0, 0), const Vec3(1, 1)), isNull);
      expect(PoseMath.jointAngle(const Vec3(1, 1), const Vec3(0, 0), const Vec3(0, 0)), isNull);
      expect(PoseMath.jointAngle(const Vec3(double.nan, 0), const Vec3(0, 0), const Vec3(1, 1)), isNull);
      expect(PoseMath.jointAngle(const Vec3(1, 0), const Vec3(0, double.infinity), const Vec3(1, 1)), isNull);
    });

    test('lean from vertical', () {
      expect(PoseMath.leanFromVertical(const Vec3(0, 1), const Vec3(0, 0)), closeTo(0, 1e-9));
      expect(PoseMath.leanFromVertical(const Vec3(0, 0), const Vec3(1, 0)), closeTo(90, 1e-9));
      expect(PoseMath.leanFromVertical(const Vec3(0, 0), const Vec3(0, 0)), isNull);
    });

    test('the synthetic fixture produces the requested knee angle', () {
      final config = ExerciseFormRules.forExercise('squat')!;
      for (final angle in [60.0, 90.0, 135.0, 170.0]) {
        final m = PoseAnalyzer.measure(squatFrame(angle, 0, torsoLean: 25), config)!;
        expect(m.primaryAngle, closeTo(angle, 1e-6));
        expect(m.torsoLean, closeTo(25, 1e-6));
      }
    });
  });

  group('Landmark validation', () {
    test('no pose, wrong landmark count and low visibility are handled without throwing', () {
      final engine = _engine();
      final none = engine.process(const PoseFrame(landmarks: [], timestampMs: 0));
      expect(none.landmarksDetected, isFalse);
      expect(none.anglesCalculated, isFalse);

      final short = engine.process(PoseFrame(landmarks: List.filled(10, const PoseLandmark(0, 0, 0, 1)), timestampMs: 33));
      expect(short.landmarksDetected, isFalse);

      final hidden = engine.process(squatFrame(170, 66, visibility: 0.2));
      expect(hidden.landmarksDetected, isTrue);
      expect(hidden.anglesCalculated, isFalse);
      expect(hidden.measurements, isNull);
    });

    test('NaN coordinates are rejected', () {
      final frame = squatFrame(170, 0);
      final broken = List<PoseLandmark>.of(frame.landmarks);
      for (final i in [PoseIndex.leftKnee, PoseIndex.rightKnee]) {
        broken[i] = const PoseLandmark(double.nan, double.nan, 0, 0.99);
      }
      final result = _engine().process(PoseFrame(landmarks: broken, timestampMs: 0));
      expect(result.anglesCalculated, isFalse);
    });

    test('one visible side is enough', () {
      final frame = squatFrame(120, 0);
      final oneSide = List<PoseLandmark>.of(frame.landmarks);
      for (final i in [PoseIndex.rightHip, PoseIndex.rightKnee, PoseIndex.rightAnkle]) {
        oneSide[i] = PoseLandmark(oneSide[i].x, oneSide[i].y, 0, 0.1);
      }
      final m = PoseAnalyzer.measure(PoseFrame(landmarks: oneSide, timestampMs: 0), ExerciseFormRules.forExercise('squat')!)!;
      expect(m.leftPrimary, closeTo(120, 1e-6));
      expect(m.rightPrimary, isNull);
      expect(m.primaryAngle, closeTo(120, 1e-6));
    });
  });

  group('Repetition counting', () {
    test('counts one rep per complete down-and-up cycle', () {
      final engine = _engine();
      final results = _run(engine, Motion().hold(400).squat().squat().squat());
      expect(engine.reps, 3);
      expect(engine.partialReps, 0);
      expect(results.where((r) => r.repEvent?.counted == true).length, 3);
    });

    test('does not count until the cycle is complete', () {
      final engine = _engine();
      _run(engine, Motion().hold(400).moveTo(88, 900).hold(500));
      expect(engine.reps, 0, reason: 'still at the bottom');
    });

    test('a shallow movement is a partial attempt, not a rep', () {
      final engine = _engine();
      _run(engine, Motion().hold(400).squat(depth: 125));
      expect(engine.reps, 0);
      expect(engine.partialReps, 1);
    });

    test('bouncing at the bottom counts once', () {
      final engine = _engine();
      final motion = Motion().hold(400).moveTo(88, 800).moveTo(120, 300).moveTo(88, 300).moveTo(125, 300).moveTo(90, 300);
      _run(engine, motion.moveTo(172, 800).hold(300));
      expect(engine.reps, 1);
    });

    test('jitter around standing does not count', () {
      final engine = _engine();
      final motion = Motion().hold(400);
      for (var i = 0; i < 30; i++) {
        motion.moveTo(i.isEven ? 163 : 176, 66);
      }
      _run(engine, motion);
      expect(engine.reps, 0);
      expect(engine.partialReps, 0);
    });

    test('a single-frame landmark glitch is ignored', () {
      final counter = RepCounter(ExerciseFormRules.forExercise('squat')!);
      var t = 0;
      for (var i = 0; i < 10; i++) {
        counter.update(172, t += 33);
      }
      counter.update(60, t += 33); // glitch
      for (var i = 0; i < 10; i++) {
        counter.update(172, t += 33);
      }
      expect(counter.phase, RepPhase.top);
      expect(counter.count, 0);
      expect(counter.partialAttempts, 0);
    });

    test('an impossibly fast cycle is discarded as noise', () {
      final engine = _engine();
      _run(engine, Motion().hold(400).moveTo(88, 130).moveTo(172, 130).hold(300));
      expect(engine.reps, 0);
      expect(engine.partialReps, 0);
    });

    test('losing tracking mid-rep drops that rep and requires the start position again', () {
      final engine = _engine();
      final down = Motion().hold(400).moveTo(88, 900);
      _run(engine, down);
      // Three seconds with nobody in frame, then the user is standing again.
      final back = Motion(startMs: down.nowMs + 3000).hold(400);
      _run(engine, back);
      expect(engine.reps, 0);
      _run(engine, Motion(startMs: back.nowMs).squat());
      expect(engine.reps, 1);
    });

    test('must start from the extended position', () {
      final engine = _engine();
      _run(engine, Motion(startAngle: 90).hold(300).moveTo(172, 900).hold(300));
      expect(engine.reps, 0);
    });

    test('thresholds are exercise-specific', () {
      // 105° is deep enough for sit-to-stand (110°) but not for a squat (100°).
      final squat = _engine('squat');
      final chair = _engine('chair_squat');
      _run(squat, Motion().hold(400).squat(depth: 105));
      _run(chair, Motion().hold(400).squat(depth: 105));
      expect(squat.reps, 0);
      expect(chair.reps, 1);
      expect(ExerciseFormRules.forExercise('pushup')!.primaryJoint, 'Elbow');
    });
  });

  group('Feedback', () {
    test('changes when the form changes', () {
      final engine = _engine();
      final good = _run(engine, Motion().hold(400).moveTo(95, 900));
      expect(good.last.feedback.isWarning, isFalse);

      final leaning = _run(engine, Motion(startMs: 2000, startAngle: 95).hold(400, torsoLean: 75));
      expect(leaning.last.feedback.isWarning, isTrue);
      expect(leaning.last.feedback.message, contains('back straight'));
      expect(leaning.last.feedback.highlight, contains(PoseIndex.leftHip));
    });

    test('a correction appears within one second of the fault', () {
      final engine = _engine();
      _run(engine, Motion().hold(400).moveTo(100, 900));
      final faulty = Motion(startMs: 1400, startAngle: 100).hold(1000, torsoLean: 75);
      final results = _run(engine, faulty);
      final firstWarning = results.indexWhere((r) => r.feedback.isWarning);
      expect(firstWarning, isNonNegative);
      expect((firstWarning + 1) * 33, lessThan(1000));
    });

    test('a shallow attempt asks for more depth', () {
      final engine = _engine();
      final results = _run(engine, Motion().hold(400).squat(depth: 125));
      expect(results.any((r) => r.feedback.isWarning && r.feedback.message == 'Lower your hips more'), isTrue);
    });
  });

  group('Score', () {
    test('is unavailable until an attempt has finished', () {
      final engine = _engine();
      _run(engine, Motion().hold(1000));
      expect(engine.postureScore, isNull);
      expect(engine.accuracy, isNull);
      final report = engine.buildReport();
      expect(report.postureScore, isNull);
      expect(report.feedback.first.verdict, FeedbackVerdict.notAssessed);
    });

    test('is the percentage of attempted reps done with acceptable form', () {
      final engine = _engine();
      _run(engine, Motion().hold(400).squat().squat().squat(depth: 125));
      expect(engine.reps, 2);
      expect(engine.partialReps, 1);
      expect(engine.postureScore, 67);
    });

    test('a rep with a posture fault lowers the score', () {
      final engine = _engine();
      _run(engine, Motion().hold(400).squat().squat(torsoLean: 75));
      expect(engine.reps, 2);
      expect(engine.postureScore, 50);
      final torso = engine.buildReport().feedback.firstWhere((f) => f.id == 'torso');
      expect(torso.verdict, FeedbackVerdict.failed);
      expect(torso.text, contains('1 of 2 reps'));
    });

    test('is deterministic and always within 0..100', () {
      int? run(double lean, double depth) {
        final engine = _engine();
        _run(engine, Motion().hold(400).squat(torsoLean: lean, depth: depth).squat().squat(depth: depth));
        return engine.postureScore;
      }

      for (final lean in [5.0, 40.0, 61.0, 89.0]) {
        for (final depth in [70.0, 99.0, 101.0, 139.0]) {
          final first = run(lean, depth);
          expect(first, run(lean, depth));
          expect(first, inInclusiveRange(0, 100));
        }
      }
    });

    test('frames without confident landmarks do not affect score or accuracy', () {
      final clean = _engine();
      _run(clean, Motion().hold(400).squat());

      final noisy = _engine();
      for (final frame in (Motion().hold(400).squat()).frames) {
        noisy.process(frame);
        // An unusable frame between every good one.
        noisy.process(squatFrame(40, frame.timestampMs + 1, torsoLean: 85, visibility: 0.1));
      }
      expect(noisy.reps, clean.reps);
      expect(noisy.postureScore, clean.postureScore);
      expect(noisy.accuracy, clean.accuracy);
      expect(noisy.buildReport().validFrames, lessThan(noisy.buildReport().totalFrames));
    });

    test('the report covers at least three form criteria per exercise', () {
      for (final id in ExerciseFormRules.supportedIds) {
        final engine = _engine(id);
        expect(engine.buildReport().feedback.length, greaterThanOrEqualTo(3), reason: id);
      }
    });

    test('a clean session reports passes and full marks', () {
      final engine = _engine();
      _run(engine, Motion().hold(400).squat().squat().squat());
      final report = engine.buildReport();
      expect(report.postureScore, 100);
      expect(report.accuracy, 100);
      expect(report.feedback.firstWhere((f) => f.id == 'depth').verdict, FeedbackVerdict.passed);
      expect(report.feedback.firstWhere((f) => f.id == 'torso').verdict, FeedbackVerdict.passed);
      expect(report.feedback.firstWhere((f) => f.id == 'tempo').verdict, FeedbackVerdict.passed);
      // Side-on, so knee tracking cannot be judged and is reported as such.
      expect(report.feedback.firstWhere((f) => f.id == 'knees').verdict, FeedbackVerdict.notAssessed);
    });
  });
}
