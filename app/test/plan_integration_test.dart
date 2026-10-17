import 'dart:convert';
import 'dart:io';

import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/workout_readiness.dart';
import 'package:app/models/workout_session.dart';
import 'package:app/screens/posture_detection/exercise_picker.dart';
import 'package:app/screens/posture_detection/posture_home.dart';
import 'package:app/screens/posture_detection/posture_mode.dart';
import 'package:app/screens/workout_and_exercise/exercise_detail.dart';
import 'package:app/services/exercise_catalog.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/plan_generator.dart';
import 'package:app/services/user_session.dart';
import 'package:app/services/workout_session/plan_progress.dart';
import 'package:app/services/workout_session/workout_log_service.dart';
import 'package:app/services/workout_session/workout_session_controller.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/session_fakes.dart';

/// Module 4 ↔ Module 5: plan exercises reachable from Posture Detection, and sessions completing planned exercises.

HealthProfile _person({int freq = 6}) => HealthProfile(
      fullName: 'Plan Tester',
      dob: '1996-04-04',
      gender: 'Female',
      heightValue: 168,
      weightValue: 64,
      medicalConditions: const [],
      primaryGoal: 'Maintain & Stay Fit',
      activityLevel: 'Moderately Active',
      workoutFrequency: freq,
    );

void main() {
  late FoodDatabase foods;
  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    ExerciseCatalog.loadFromJsonString(File('assets/data/exercise_catalog.json').readAsStringSync());
    foods = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
  });

  PersonalizedPlan plan() => PlanGenerator(foods).generate(_person(), const RuleBasedClassifier().classify(_person()),
      readiness: const WorkoutReadiness(clearance: true));

  // 2026-10-19 is a Monday (weekday index 0).
  final monday = DateTime(2026, 10, 19, 18);

  group('Planned-exercise completion (PlanProgress)', () {
    late PersonalizedPlan p;
    late FakeStore store;
    late List<String> marked;
    late PlanProgress progress;
    var planId = 'plan-a';

    setUp(() {
      p = plan();
      store = FakeStore();
      marked = [];
      planId = 'plan-a';
      progress = PlanProgress(
        store: store,
        currentPlan: () => p,
        currentPlanId: () => planId,
        weightKg: () => 64,
        markDay: (date, day, kg) async => marked.add('${PlanProgress.dateKey(date)} ${day.name}'),
        now: () => monday,
      );
    });

    SessionSummary summary(int entry, {bool completed = true, int weekday = 0, String? id}) {
      final day = p.week[weekday]!;
      return SessionSummary(
        exercise: SessionExercise.fromPlanned(day.exercises[entry]),
        mode: SessionMode.camera,
        endedAt: monday,
        duration: const Duration(minutes: 2),
        reps: 10,
        plan: PlanLink(planId: id ?? planId, weekday: weekday, entryIndex: entry, date: '2026-10-19'),
        completedTarget: completed,
      );
    }

    test('only a session that reached its target completes the planned exercise', () async {
      await progress.record(summary(1, completed: false));
      expect(progress.isDoneToday(0, 1), isFalse);
      await progress.record(summary(1));
      expect(progress.isDoneToday(0, 1), isTrue);
    });

    test('completing every main exercise marks the day done once, through the Module 4 activity record', () async {
      final main = PlanProgress.mainEntries(p.week[0]!);
      expect(main, isNotEmpty);
      expect(main, isNot(contains(0)), reason: 'the warm-up does not count');
      for (final i in main.take(main.length - 1)) {
        await progress.record(summary(i));
      }
      expect(marked, isEmpty, reason: 'not all done yet');
      await progress.record(summary(main.last));
      expect(marked, ['2026-10-19 ${p.week[0]!.name}']);
      await progress.record(summary(main.last)); // the same exercise again
      await progress.record(summary(main.first));
      expect(marked, hasLength(1), reason: 'no duplicate completion records');
      expect(progress.dayMarkedToday(0), isTrue);
    });

    test("another day's exercises are saved but do not complete today", () async {
      for (final i in PlanProgress.mainEntries(p.week[1]!)) {
        await progress.record(summary(i, weekday: 1));
      }
      expect(marked, isEmpty);
    });

    test('a regenerated plan does not inherit the old plan\'s progress', () async {
      await progress.record(summary(1));
      planId = 'plan-b';
      expect(progress.completedToday(0), isEmpty);
    });

    test('progress is read back from saved sessions after a restart', () async {
      await store.save(summary(1));
      await store.save(summary(2, completed: false));
      await store.save(summary(3, id: 'old-plan'));
      await progress.loadToday();
      expect(progress.completedToday(0), {1});
    });

    test('library sessions (no plan link) are independent workouts', () async {
      await progress.record(SessionSummary(
          exercise: SessionExercise.fromExercise(ExerciseLibrary.byId('squat')!),
          mode: SessionMode.camera,
          endedAt: monday,
          duration: const Duration(minutes: 1),
          reps: 30,
          completedTarget: true));
      expect(progress.completedToday(0), isEmpty);
    });
  });

  group('Session controller', () {
    test('target reached: camera reps, hold time and manual sets; never when skipped or just opened', () {
      final finished = <SessionSummary>[];
      final c = WorkoutSessionController(onFinished: finished.add);
      final squat = SessionExercise.fromExercise(ExerciseLibrary.byId('squat')!, sets: 2); // 2 × base reps
      const link = PlanLink(planId: 'x', weekday: 0, entryIndex: 2, date: '2026-10-19');

      c.start(WorkoutSessionRequest(exercise: squat, plan: link), SessionMode.camera);
      expect(c.finish().completedTarget, isFalse, reason: 'opened the camera, no reps');
      c.start(WorkoutSessionRequest(exercise: squat, plan: link), SessionMode.manual);
      c.recordManualSet(squat.reps);
      c.recordManualSet(squat.reps);
      final done = c.finish();
      expect(done.completedTarget, isTrue);
      expect(done.plan, link);
      c.start(WorkoutSessionRequest(exercise: squat, plan: link), SessionMode.manual);
      c.recordManualSet(squat.reps);
      c.recordManualSet(squat.reps);
      expect(c.finish(skipped: true).completedTarget, isFalse);
      expect(finished, hasLength(3));
    });

    test('the next exercise in the sequence gets the next plan entry', () {
      final day = plan().week[0]!;
      const link = PlanLink(planId: 'x', weekday: 0, entryIndex: 1, date: '2026-10-19');
      final req = WorkoutSessionRequest.fromPlanned(day.exercises[1], upNext: day.exercises.sublist(2), plan: link);
      expect(req.next!.plan!.entryIndex, 2);
      expect(req.next!.exercise.id, day.exercises[2].exercise.id);
    });
  });

  group('Saved session schema', () {
    Map<String, dynamic> sessionRules() {
      final rules = jsonDecode(File('database.rules.json').readAsStringSync()) as Map<String, dynamic>;
      return ((rules['rules'] as Map)['users'] as Map)[r'$uid']['workoutSessions'][r'$session'] as Map<String, dynamic>;
    }

    SessionSummary linked() => SessionSummary(
          exercise: SessionExercise.fromExercise(ExerciseLibrary.byId('squat')!),
          mode: SessionMode.camera,
          endedAt: DateTime(2026, 10, 19),
          duration: const Duration(seconds: 90),
          reps: 24,
          plan: const PlanLink(planId: 'abcd1234', weekday: 0, entryIndex: 3, date: '2026-10-19'),
          completedTarget: true,
        );

    test('every field the app writes is accepted by database.rules.json', () {
      final allowed = sessionRules().keys.where((k) => !k.startsWith('.') && !k.startsWith(r'$')).toSet();
      final json = WorkoutLog.toJson(linked());
      expect(allowed.containsAll(json.keys), isTrue, reason: 'not in rules: ${json.keys.toSet().difference(allowed)}');
      expect(json['planEntry'], 3);
      expect(json['planCompleted'], isTrue);
    });

    test('the fallback record leaves the plan link out', () {
      final json = WorkoutLog.toJson(linked(), withPlan: false);
      expect(json.keys.where((k) => k.startsWith('plan')), isEmpty);
      expect(json['reps'], 24);
    });
  });

  group('Posture Detection home', () {
    tearDown(() {
      UserSession.instance.clear();
      UserSession.instance.loading = false;
      PlanProgress.instance.reset();
    });

    Future<void> pump(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: screen));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('loading shows a spinner, not "no plan"', (tester) async {
      UserSession.instance.loading = true;
      await pump(tester, const PostureDetectionHome());
      expect(find.byKey(const ValueKey('plan-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-empty')), findsNothing);
    });

    testWidgets('no plan: an empty state with a way to create one; the library still works', (tester) async {
      await pump(tester, const PostureDetectionHome());
      expect(find.text('No personalised plan yet'), findsOneWidget);
      expect(find.text('Create my health profile'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tab-library')));
      await tester.pumpAndSettle();
      expect(find.byType(ExerciseLibraryList), findsOneWidget);
      expect(find.text('Camera posture detection'), findsOneWidget);
    });

    testWidgets("today's workout and the whole week come from the user's own plan", (tester) async {
      UserSession.instance.readiness = const WorkoutReadiness(clearance: true);
      await tester.runAsync(() => UserSession.instance.setProfile(_person()));
      final p = UserSession.instance.plan!;
      final today = DateTime.now().weekday - 1;
      await pump(tester, const PostureDetectionHome());

      final todayDay = p.week[today];
      if (todayDay == null) {
        expect(find.byKey(const ValueKey('rest-day')), findsOneWidget);
      } else {
        expect(find.byKey(ValueKey('entry-$today-1')), findsOneWidget);
        expect(find.text(todayDay.exercises[1].exercise.name), findsWidgets);
      }

      await tester.tap(find.byKey(const ValueKey('tab-plan')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('day-6'))); // Sunday: 6-day plans rest on Sunday
      await tester.pumpAndSettle();
      expect(p.week[6], isNull);
      expect(find.text('Sunday is a rest day'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('day-0')));
      await tester.pumpAndSettle();
      final monday = p.week[0]!;
      final entry = find.byKey(const ValueKey('entry-0-2'));
      expect(entry, findsOneWidget);
      expect(find.byKey(const ValueKey('capability-0-2')), findsOneWidget);

      await tester.tap(entry);
      await tester.pumpAndSettle();
      final mode = tester.widget<PostureModeSelection>(find.byType(PostureModeSelection));
      expect(mode.request.exercise.id, monday.exercises[2].exercise.id);
      expect(mode.request.exercise.sets, monday.exercises[2].sets);
      expect(mode.request.exercise.movement, monday.exercises[2].exercise.movement);
      expect(mode.request.plan!.weekday, 0);
      expect(mode.request.plan!.entryIndex, 2);
      expect(mode.request.plan!.planId, UserSession.instance.planId);
    });

    testWidgets('a completed planned exercise shows as done today', (tester) async {
      UserSession.instance.readiness = const WorkoutReadiness(clearance: true);
      await tester.runAsync(() => UserSession.instance.setProfile(_person()));
      final today = PlanProgress.instance.todayIndex;
      final day = UserSession.instance.plan!.week[today];
      if (day == null) return; // a rest day today: nothing to complete
      await pump(tester, const PostureDetectionHome());
      expect(find.text('Done today'), findsNothing);
      await tester.runAsync(() => PlanProgress.instance.record(SessionSummary(
            exercise: SessionExercise.fromPlanned(day.exercises[1]),
            mode: SessionMode.manual,
            endedAt: DateTime.now(),
            duration: const Duration(minutes: 1),
            reps: 10,
            plan: PlanProgress.instance.linkFor(today, 1),
            completedTarget: true,
          )));
      await tester.pump();
      expect(find.text('Done today'), findsOneWidget);
    });

    testWidgets('Start exercise in the workout plan links the session to its plan entry', (tester) async {
      UserSession.instance.readiness = const WorkoutReadiness(clearance: true);
      await tester.runAsync(() => UserSession.instance.setProfile(_person()));
      final day = UserSession.instance.plan!.week[0]!;
      await pump(tester, ExerciseDetail(planned: day.exercises[3], queue: day.exercises, weekday: 0));
      await tester.tap(find.text('Start exercise'));
      await tester.pumpAndSettle();
      final mode = tester.widget<PostureModeSelection>(find.byType(PostureModeSelection));
      expect(mode.request.plan!.entryIndex, 3);
      expect(mode.request.upNext.length, day.exercises.length - 4);
    });
  });
}
