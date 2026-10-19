import 'dart:convert';
import 'dart:io';

import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/workout_session.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/plan_generator.dart';
import 'package:app/services/workout_session/workout_log_service.dart';
import 'package:app/services/workout_session/workout_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pose_fixtures.dart';
import 'support/session_fakes.dart';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

HealthProfile _profile() => HealthProfile(
      fullName: 'Test User',
      dob: '1998-05-01',
      gender: 'Female',
      heightValue: 165,
      weightValue: 70,
      primaryGoal: 'Gain Muscle',
      activityLevel: 'Moderately Active',
      workoutFrequency: 4,
    );

void main() {
  late FoodDatabase foods;

  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    foods = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
  });

  group('Saving sessions', () {
    test('a finished session is saved once, with its "too difficult" mark', () async {
      final store = FakeStore();
      final flaggedLocally = <String>[];
      final session = WorkoutSessionController(store: store, onTooDifficult: flaggedLocally.add)
        ..start(const WorkoutSessionRequest(exercise: squatExercise), SessionMode.manual)
        ..recordManualSet(12);
      session.finish(tooDifficult: true);
      expect(session.saveState.value, SaveState.saving);
      await _flush();
      expect(session.saveState.value, SaveState.saved);
      expect(store.saved.single.reps, 12);
      expect(store.flagged, ['squat']);
      expect(flaggedLocally, ['squat']);

      await session.retrySave();
      expect(store.saved.length, 1, reason: 'not written twice');
    });

    test('a failed save can be retried without duplicating what already succeeded', () async {
      final store = FakeStore()..failFlags = 1;
      final session = WorkoutSessionController(store: store)
        ..start(const WorkoutSessionRequest(exercise: squatExercise), SessionMode.manual);
      session.finish(tooDifficult: true);
      await _flush();
      expect(session.saveState.value, SaveState.failed);
      expect(session.saveError, 'Could not reach the database.');
      expect(store.saved.length, 1);

      await session.retrySave();
      expect(session.saveState.value, SaveState.saved);
      expect(store.saved.length, 1);
      expect(store.flagged, ['squat']);
    });

    test('without a store nothing is attempted', () async {
      final session = WorkoutSessionController()
        ..start(const WorkoutSessionRequest(exercise: squatExercise), SessionMode.manual);
      session.finish();
      await _flush();
      expect(session.saveState.value, SaveState.idle);
    });

    test('the stored record only uses fields the database rules accept', () {
      final rules = jsonDecode(File('database.rules.json').readAsStringSync()) as Map<String, dynamic>;
      final sessionRules =
          (rules['rules']['users'][r'$uid']['workoutSessions'][r'$session'] as Map<String, dynamic>);
      final allowed = sessionRules.keys.where((k) => !k.startsWith('.') && !k.startsWith(r'$')).toSet();
      final required = RegExp(r"'(\w+)'").allMatches(sessionRules['.validate'] as String).map((m) => m[1]).toSet();

      final summary = SessionSummary(
        exercise: squatExercise,
        mode: SessionMode.camera,
        endedAt: DateTime(2026, 10, 14, 9),
        duration: const Duration(minutes: 3, seconds: 5),
        reps: 10,
        partialReps: 2,
        postureScore: 80,
        accuracy: 91,
        averageFps: 17.36,
        feedback: const [
          FormFeedbackItem(id: 'depth', verdict: FeedbackVerdict.failed, text: 'Hip depth could be lower in 2 of 12 attempts'),
        ],
      );
      final json = WorkoutLog.toJson(summary);
      expect(allowed.containsAll(json.keys), isTrue, reason: '${json.keys.toSet().difference(allowed)}');
      expect(json.keys.toSet().containsAll(required), isTrue);
      expect(json['mode'], 'camera');
      expect(json['durationSec'], 185);
      expect(json['averageFps'], 17.4);
      final feedback = (json['feedback'] as Map)['0'] as Map;
      expect(feedback['verdict'], 'failed');

      final manual = WorkoutLog.toJson(SessionSummary(
        exercise: plankExercise,
        mode: SessionMode.manual,
        endedAt: DateTime(2026),
        duration: Duration.zero,
        reps: 0,
      ));
      expect(manual.containsKey('postureScore'), isFalse, reason: 'no score is invented for manual sessions');
    });
  });

  group('"Too Difficult" adjusts the next plan', () {
    List<PlannedExercise> mains(PersonalizedPlan plan) => [
          for (final day in plan.week.whereType<WorkoutDay>())
            for (final p in day.exercises)
              if (p.exercise.id != 'warmup' && p.exercise.id != 'cooldown') p,
        ];

    test('a flagged exercise is replaced by an easier or equal one of the same group', () {
      final p = _profile();
      final cls = const RuleBasedClassifier().classify(p);
      final before = PlanGenerator(foods).generate(p, cls);
      final target = mains(before).firstWhere((e) => e.exercise.group == 'legs').exercise;

      final after = PlanGenerator(foods).generate(p, cls, tooDifficult: {target.id});
      final ids = mains(after).map((e) => e.exercise.id).toSet();
      expect(ids, isNot(contains(target.id)));
      expect(after.restrictionNotes.last, contains('too difficult'));
      expect(after.restrictionNotes.last, contains(target.name));
      // The note names the replacement; it must be no harder than the original.
      final swap = RegExp('${RegExp.escape(target.name)} → ([^;.]+)').firstMatch(after.restrictionNotes.last);
      expect(swap, isNotNull);
      final replacement = ExerciseLibrary.all.firstWhere((e) => e.name == swap![1]);
      expect(replacement.group, target.group);
      expect(replacement.level, lessThanOrEqualTo(target.level));
      expect(ids, contains(replacement.id));
    });

    test('with no easier alternative the exercise stays with a lighter dose', () {
      final p = _profile();
      final cls = const RuleBasedClassifier().classify(p);
      final before = PlanGenerator(foods).generate(p, cls);
      final legs = {for (final e in ExerciseLibrary.all) if (e.group == 'legs') e.id};

      final after = PlanGenerator(foods).generate(p, cls, tooDifficult: legs);
      final legPlans = [for (final e in mains(after)) if (e.exercise.group == 'legs') e];
      expect(legPlans, isNotEmpty, reason: 'the slot is still filled');
      final beforeById = {for (final e in mains(before)) e.exercise.id: e};
      for (final e in legPlans) {
        final original = beforeById[e.exercise.id];
        if (original == null) continue;
        expect(e.sets, lessThanOrEqualTo(original.sets));
        if (!e.timed) expect(e.reps, lessThan(original.reps));
      }
      expect(after.restrictionNotes.last, contains('lighter dose'));
    });

    test('no flags: the plan is unchanged', () {
      final p = _profile();
      final cls = const RuleBasedClassifier().classify(p);
      final a = mains(PlanGenerator(foods).generate(p, cls)).map((e) => e.exercise.id).toList();
      final b = mains(PlanGenerator(foods).generate(p, cls, tooDifficult: const {})).map((e) => e.exercise.id).toList();
      expect(b, a);
    });
  });
}
