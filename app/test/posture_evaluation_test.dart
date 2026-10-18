import 'dart:io';

import 'package:app/models/movement_pattern.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/workout_readiness.dart';
import 'package:app/models/workout_session.dart';
import 'package:app/services/exercise_catalog.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/exercise_repository.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/services/plan_generator.dart';
import 'package:app/services/posture/exercise_form_rules.dart';
import 'package:app/services/posture/form_checks.dart';
import 'package:app/services/posture/movement_patterns.dart';
import 'package:app/services/posture/pose_landmark.dart';
import 'package:app/services/posture/posture_engine.dart';
import 'package:app/services/workout_rules/classification_profiles.dart';
import 'package:app/services/workout_rules/safety_rule_engine.dart';
import 'package:app/services/workout_rules/safety_rule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/body_fixtures.dart';

/// Module 5: real posture evaluation for the movement patterns (experimental level), checked on synthetic whole-body
/// poses. These tests show the checks measure and react to the right thing; they are NOT evidence of accuracy on real
/// people — that needs the device validation in docs/MODULE5_DEVICE_VALIDATION.md.

ExerciseFormConfig _cfg(String id, MovementPattern p) => MovementPatterns.resolve(id, p).form!;

/// Feeds frames and returns every live feedback message.
List<String> _run(PostureEngine engine, Iterable<PoseFrame> frames) => [for (final f in frames) engine.process(f).feedback.message];

void main() {
  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    ExerciseCatalog.loadFromJsonString(File('assets/data/exercise_catalog.json').readAsStringSync());
  });

  group('Measurements', () {
    test('hip position against the body line: sag is negative, pike positive, straight is zero', () {
      final c = _cfg('Pushups', MovementPattern.pushup);
      expect(PoseAnalyzer.measure(plankBody(0), c)!.hipOffset!, closeTo(0, 0.01));
      expect(PoseAnalyzer.measure(plankBody(0, hipOffset: -0.1), c)!.hipOffset!, closeTo(-0.1, 0.01));
      expect(PoseAnalyzer.measure(plankBody(0, hipOffset: 0.15), c)!.hipOffset!, closeTo(0.15, 0.01));
      expect(PoseAnalyzer.measure(sideBody(0, elbow: 120), c)!.hipOffset, isNull, reason: 'standing: no body line to judge');
    });

    test('secondary angles, symmetry and foot spread are measured only when observable', () {
      final c = _cfg('Dumbbell_Bicep_Curl', MovementPattern.curl);
      final m = PoseAnalyzer.measure(sideBody(0, arm: 40, elbow: 90, knee: 150, hip: 120), c)!;
      expect(m.upperArmAngle!, closeTo(40, 1));
      expect(m.elbowAngle!, closeTo(90, 1));
      expect(m.kneeAngle!, closeTo(150, 1));
      expect(m.hipAngle!, closeTo(120, 1));
      expect(m.armAsymmetry, isNull, reason: 'side view');
      final jack = _cfg('jumping_jacks', MovementPattern.jumpingJack);
      final f = PoseAnalyzer.measure(frontBody(0, arms: 150, feet: 2.2), jack)!;
      expect(f.facingCamera, isTrue);
      expect(f.ankleSpread!, closeTo(2.2, 0.05));
      final press = _cfg('Dumbbell_Shoulder_Press', MovementPattern.overheadPress);
      expect(PoseAnalyzer.measure(frontBody(0, arms: 60, armDifference: 40), press)!.armAsymmetry, isNotNull);
    });
  });

  group('Checks: correct form passes, the measured fault is reported with the right correction', () {
    test('hips sagging vs piking give opposite corrections', () {
      const check = HipLineCheck();
      const sag = PoseMeasurements(primaryAngle: 170, hipOffset: -0.12);
      const pike = PoseMeasurements(primaryAngle: 170, hipOffset: 0.2);
      expect(check.evaluate(const PoseMeasurements(primaryAngle: 170, hipOffset: 0.01)), CheckOutcome.pass);
      expect(check.evaluate(sag), CheckOutcome.fail);
      expect(check.cueFor(sag), contains('Raise your hips'));
      expect(check.cueFor(pike), contains('Lower your hips'));
      expect(check.evaluate(const PoseMeasurements(primaryAngle: 170)), CheckOutcome.notApplicable);
    });

    test('a range check reads its own measurement and can be limited to the turning point', () {
      const feet = JointRangeCheck(
          id: 'f', label: 'f', measure: Measure.knee, min: 60, max: 125, atPeakOnly: true, lowCue: 'low', highCue: 'high', passedText: '', failedText: '');
      expect(feet.evaluate(const PoseMeasurements(primaryAngle: 160, kneeAngle: 150)), CheckOutcome.notApplicable, reason: 'not at the peak');
      const tooFar = PoseMeasurements(primaryAngle: 170, kneeAngle: 150, atPeak: true);
      expect(feet.evaluate(tooFar), CheckOutcome.fail);
      expect(feet.cueFor(tooFar), 'high');
      expect(feet.evaluate(const PoseMeasurements(primaryAngle: 170, kneeAngle: 90, atPeak: true)), CheckOutcome.pass);
    });

    test('symmetry and sway are not applicable without the measurement', () {
      expect(const ArmSymmetryCheck(25).evaluate(const PoseMeasurements(primaryAngle: 100)), CheckOutcome.notApplicable);
      expect(const TorsoSwayCheck(10).evaluate(const PoseMeasurements(primaryAngle: 100)), CheckOutcome.notApplicable);
      expect(const ArmSymmetryCheck(25).evaluate(const PoseMeasurements(primaryAngle: 100, armAsymmetry: 40)), CheckOutcome.fail);
    });
  });

  group('End to end through the engine (experimental level)', () {
    test('curl: a still upper arm gets no correction; swinging it forward does', () {
      final c = _cfg('Dumbbell_Bicep_Curl', MovementPattern.curl);
      List<PoseFrame> reps(double arm) => [
            ...sweep((t, v) => sideBody(t, elbow: v, arm: 5), 165, 165, 400),
            for (var r = 0; r < 2; r++) ...[
              ...sweep((t, v) => sideBody(t, elbow: v, arm: arm), 165, 55, 800, startMs: 500 + r * 2000),
              ...sweep((t, v) => sideBody(t, elbow: v, arm: arm), 55, 165, 800, startMs: 1300 + r * 2000),
              ...sweep((t, v) => sideBody(t, elbow: v, arm: 5), 165, 165, 300, startMs: 2100 + r * 2000),
            ],
          ];
      final good = PostureEngine(c);
      final goodMessages = _run(good, reps(10));
      expect(good.reps, 2);
      expect(goodMessages.any((m) => m.contains('upper arm')), isFalse);
      final goodReport = good.buildReport();
      expect(goodReport.postureScore, 100, reason: 'both reps acceptable');
      expect(goodReport.feedback.firstWhere((f) => f.id == 'upper_arm').verdict, FeedbackVerdict.passed);

      final bad = PostureEngine(c);
      final badMessages = _run(bad, reps(60));
      expect(badMessages, contains('Keep your upper arm still, close to your body'));
      expect(bad.buildReport().feedback.firstWhere((f) => f.id == 'upper_arm').verdict, FeedbackVerdict.failed);
      expect(bad.postureScore, 0, reason: 'every rep had the fault');
    });

    test('curl: leaning back to lift is caught as torso sway relative to the starting posture', () {
      final c = _cfg('Dumbbell_Bicep_Curl', MovementPattern.curl);
      final engine = PostureEngine(c);
      final messages = _run(engine, [
        ...sweep((t, v) => sideBody(t, elbow: 165), 0, 0, 500),
        ...sweep((t, v) => sideBody(t, elbow: v, lean: (165 - v) / 110 * 25), 165, 55, 900, startMs: 600),
        ...sweep((t, v) => sideBody(t, elbow: v, lean: (165 - v) / 110 * 25), 55, 165, 900, startMs: 1500),
      ]);
      expect(messages, contains("Keep your body still — don't swing"));
    });

    test('lunge: an upright torso passes; folding forward is corrected', () {
      final c = _cfg('Dumbbell_Lunges', MovementPattern.lunge);
      List<String> run(double lean) => _run(PostureEngine(c), [
            ...sweep((t, v) => sideBody(t, knee: 170, lean: 5), 0, 0, 400),
            ...sweep((t, v) => sideBody(t, knee: v, hip: v, lean: lean), 170, 95, 900, startMs: 500),
            ...sweep((t, v) => sideBody(t, knee: v, hip: v, lean: lean), 95, 170, 900, startMs: 1400),
          ]);
      expect(run(10).contains('Keep your torso upright'), isFalse);
      expect(run(50), contains('Keep your torso upright'));
    });

    test('plank hold: sagging and piking are corrected in the right direction; a straight line is timed', () {
      final c = _cfg('plank', MovementPattern.plankHold);
      final engine = PostureEngine(c);
      final straight = _run(engine, sweep((t, v) => plankBody(t), 0, 0, 3000));
      expect(straight.last, startsWith('Holding'));
      expect(engine.holdSeconds, greaterThanOrEqualTo(2));
      final sag = _run(engine, sweep((t, v) => plankBody(t, hipOffset: -0.15), 0, 0, 600, startMs: 3100));
      expect(sag.last, contains('Raise your hips'));
      final pike = _run(engine, sweep((t, v) => plankBody(t, hipOffset: 0.25), 0, 0, 600, startMs: 3800));
      expect(pike.last, contains('Lower your hips'));
      final report = engine.buildReport(targetSeconds: 30);
      expect(report.postureScore, inExclusiveRange(0, 100), reason: 'straight part counts for, sag and pike against');
      expect(report.feedback.first.id, 'experimental');
      expect(report.feedback.firstWhere((f) => f.id == 'hips').verdict, FeedbackVerdict.failed);
    });

    test('push-up (dataset entry): sagging hips during the reps are corrected', () {
      final c = _cfg('Pushups', MovementPattern.pushup);
      final messages = _run(PostureEngine(c), [
        ...sweep((t, v) => plankBody(t, elbow: 170), 0, 0, 400),
        ...sweep((t, v) => plankBody(t, elbow: v, hipOffset: -0.14), 170, 85, 900, startMs: 500),
        ...sweep((t, v) => plankBody(t, elbow: v, hipOffset: -0.14), 85, 170, 900, startMs: 1400),
      ]);
      expect(messages, contains("Raise your hips slightly — don't let them sag"));
    });

    test('jumping jack: arms up with the feet staying together is corrected at the top', () {
      final c = _cfg('jumping_jacks', MovementPattern.jumpingJack);
      List<String> run(double feetAtTop) => _run(PostureEngine(c), [
            ...sweep((t, v) => frontBody(t, arms: 15), 0, 0, 400),
            ...sweep((t, v) => frontBody(t, arms: v, feet: 1 + (feetAtTop - 1) * (v - 15) / 140), 15, 155, 500, startMs: 500),
            ...sweep((t, v) => frontBody(t, arms: 155, feet: feetAtTop), 0, 0, 300, startMs: 1000),
            // feet come back in together with the arms, as in a real jack
            ...sweep((t, v) => frontBody(t, arms: v, feet: 1 + (feetAtTop - 1) * (v - 15) / 140), 155, 15, 500, startMs: 1300),
          ]);
      expect(run(2.4).any((m) => m.contains('feet wide')), isFalse);
      expect(run(1.0), contains('Jump your feet wide as your arms go up'));
    });

    test('noise filtering: one bad frame never triggers a correction', () {
      final c = _cfg('Dumbbell_Bicep_Curl', MovementPattern.curl);
      final frames = [
        ...sweep((t, v) => sideBody(t, elbow: 165), 0, 0, 400),
        ...sweep((t, v) => sideBody(t, elbow: v), 165, 100, 400, startMs: 500),
        sideBody(940, elbow: 98, arm: 70), // a single glitch
        ...sweep((t, v) => sideBody(t, elbow: v), 98, 55, 400, startMs: 960),
      ];
      expect(_run(PostureEngine(c), frames).any((m) => m.contains('upper arm')), isFalse);
    });

    test('experimental results never claim good form', () {
      final c = _cfg('Dumbbell_Bicep_Curl', MovementPattern.curl);
      final messages = _run(PostureEngine(c), [
        ...sweep((t, v) => sideBody(t, elbow: 165), 0, 0, 400),
        ...sweep((t, v) => sideBody(t, elbow: v), 165, 55, 800, startMs: 500),
        ...sweep((t, v) => sideBody(t, elbow: v), 55, 165, 800, startMs: 1300),
      ]);
      expect(messages, isNot(contains('Great rep — good form!')));
      expect(messages.any((m) => m.contains('no form issues detected')), isTrue);
    });

    test('variants: braced curls skip the upper-arm check; one-arm presses skip symmetry', () {
      expect(ExerciseRepository.postureFor(ExerciseCatalog.byId('Preacher_Curl')!).checkLabels, isNot(contains('Upper-arm position')));
      expect(ExerciseRepository.postureFor(ExerciseCatalog.byId('Dumbbell_One-Arm_Shoulder_Press')!).checkLabels,
          isNot(contains('Arm symmetry')));
      expect(ExerciseRepository.postureFor(ExerciseCatalog.byId('Dumbbell_Shoulder_Press')!).checkLabels, contains('Arm symmetry'));
    });
  });

  group('The four validated detectors are unchanged', () {
    test('same configurations, still scored', () {
      for (final id in ['squat', 'chair_squat', 'pushup', 'knee_pushup']) {
        final c = ExerciseRepository.postureFor(ExerciseLibrary.byId(id)!);
        expect(c.level, CameraSupportLevel.validatedForm, reason: id);
        expect(c.form, same(ExerciseFormRules.forExercise(id)), reason: id);
        expect(c.showsPostureScore, isTrue);
      }
    });
  });

  group('Unified catalogue', () {
    test('one canonical id per exercise, no dataset duplicate of a curated exercise', () {
      final ids = ExerciseRepository.all.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ExerciseRepository.byId('squat')!.source, 'baymax');
      expect(ExerciseRepository.byId('Dumbbell_Bicep_Curl')!.source, 'free-exercise-db');
      expect(ids.contains('Bodyweight_Squat'), isFalse, reason: 'linked to the curated squat');
      final entry = ExerciseRepository.entry(ExerciseRepository.byId('Dumbbell_Bicep_Curl')!).toJson();
      for (final k in ['id', 'source', 'difficulty', 'movementPattern', 'postureConfigId', 'postureCapability', 'metValue', 'safetyTags']) {
        expect(entry.containsKey(k), isTrue, reason: k);
      }
      expect(entry['postureConfigId'], 'curl/experimentalForm');
    });
  });

  group('Safety: camera capability never makes an exercise eligible', () {
    test('a camera-tracked exercise the rules exclude is not scheduled (300 random people)', () {
      final foods = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
      const kit = {'dumbbell', 'barbell', 'kettlebell', 'bands', 'cable', 'machine'};
      for (var i = 0; i < 300; i++) {
        final person = HealthProfile(
          fullName: 'P$i',
          dob: '${1950 + i % 50}-01-01',
          gender: i.isEven ? 'Female' : 'Male',
          heightValue: 150 + (i * 7) % 40,
          weightValue: 45 + (i * 13) % 90,
          medicalConditions: [if (i % 5 == 0) 'Hypertension', if (i % 7 == 0) 'Diabetes', if (i % 11 == 0) 'Heart Disease'],
          primaryGoal: const ['Lose Weight', 'Gain Muscle', 'Maintain & Stay Fit'][i % 3],
          activityLevel: const ['Sedentary', 'Lightly Active', 'Moderately Active', 'Very Active'][i % 4],
          workoutFrequency: 2 + i % 5,
        );
        const readiness = WorkoutReadiness(clearance: true, equipment: kit, injuries: {});
        final cls = const RuleBasedClassifier().classify(person);
        final plan = PlanGenerator(foods).generate(person, cls, readiness: readiness);
        if (!plan.workoutAvailable) continue;
        final rulesOnly = SafetyRuleRepository.engine.assess(HealthFacts.from(person, cls, plan.intensity, readiness: readiness),
            profile: ClassificationProfiles.forCategory(cls.category));
        for (final d in plan.week.whereType<WorkoutDay>()) {
          for (final p in d.exercises) {
            expect(rulesOnly.decide(p.exercise).schedulable, isTrue, reason: '${p.exercise.id} for person $i');
          }
        }
      }
      // And the converse: jump squats are camera-tracked, yet never scheduled for someone with a BMI of 30+.
      final jump = ExerciseLibrary.byId('jump_squats')!;
      expect(ExerciseRepository.postureFor(jump).supportsCameraTracking, isTrue);
      final obese = HealthProfile(
          fullName: 'O', dob: '1990-01-01', gender: 'Female', heightValue: 160, weightValue: 95, medicalConditions: const [],
          primaryGoal: 'Lose Weight', activityLevel: 'Moderately Active', workoutFrequency: 5);
      final p = PlanGenerator(foods).generate(obese, const RuleBasedClassifier().classify(obese), readiness: const WorkoutReadiness(clearance: true));
      expect(p.week.whereType<WorkoutDay>().expand((d) => d.exercises).any((e) => e.exercise.id == 'jump_squats'), isFalse);
    });
  });

  test('required landmarks are part of every tracker configuration', () {
    for (final e in ExerciseRepository.all) {
      final c = ExerciseRepository.postureFor(e);
      if (!c.supportsCameraTracking) continue;
      expect(c.requiredLandmarks, isNotEmpty, reason: e.id);
      expect(c.requiredLandmarks.every((i) => i >= 0 && i < PoseIndex.count), isTrue);
    }
    expect(SessionExercise.fromExercise(ExerciseLibrary.byId('plank')!).movement, MovementPattern.plankHold);
  });
}
