import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/gamification.dart';

DayRecord day(DateTime d, {bool planned = false, bool done = false, bool logged = false, double? kcal, int target = 2000}) =>
    DayRecord(date: d, planned: planned, workoutDone: done, foodLogged: logged, kcal: logged ? (kcal ?? 2000) : null, targetKcal: target);

/// n consecutive days ending on [last].
List<DateTime> daysEnding(DateTime last, int n) => [for (var i = n - 1; i >= 0; i--) last.subtract(Duration(days: i))];

void main() {
  group('ISO week id', () {
    test('known dates', () {
      expect(Gamification.isoWeekId(DateTime(2026, 10, 13)), '2026-W42');
      expect(Gamification.isoWeekId(DateTime(2026, 10, 12)), '2026-W42'); // Monday
      expect(Gamification.isoWeekId(DateTime(2026, 10, 18)), '2026-W42'); // Sunday
      expect(Gamification.isoWeekId(DateTime(2026, 1, 1)), '2026-W01');
      expect(Gamification.isoWeekId(DateTime(2025, 12, 29)), '2026-W01'); // belongs to the next ISO year
      expect(Gamification.isoWeekId(DateTime(2027, 1, 3)), '2026-W53');
      expect(Gamification.isoWeekId(DateTime(2024, 12, 30)), '2025-W01');
    });
    test('week starts on Monday', () {
      expect(Gamification.weekStart(DateTime(2026, 10, 15)), DateTime(2026, 10, 12));
      expect(Gamification.weekStart(DateTime(2026, 10, 18)), DateTime(2026, 10, 12));
    });
  });

  group('weekly fitness score', () {
    final mon = DateTime(2026, 10, 12);

    test('a perfect week scores 100', () {
      final days = [for (var i = 0; i < 4; i++) day(mon.add(Duration(days: i)), planned: i.isEven, done: i.isEven, logged: true)];
      expect(Gamification.weeklyScore(days).total, closeTo(100, 1e-9));
    });

    test('nothing done scores 0', () {
      final days = [for (var i = 0; i < 4; i++) day(mon.add(Duration(days: i)), planned: true)];
      final s = Gamification.weeklyScore(days);
      expect(s.total, 0);
      expect(s.workoutsPlanned, 4);
    });

    test('parts are weighted 50 / 25 / 25', () {
      // 2 planned, 1 done (0.5) · 4 days, 2 logged (0.5) · 1 of 2 logged on target (0.5)  => 50
      final days = [
        day(mon, planned: true, done: true, logged: true, kcal: 2000),
        day(mon.add(const Duration(days: 1)), planned: true, logged: true, kcal: 900),
        day(mon.add(const Duration(days: 2))),
        day(mon.add(const Duration(days: 3))),
      ];
      expect(Gamification.weeklyScore(days).total, closeTo(50, 1e-9));
      // only training done, nothing logged: 50% of the weight
      final onlyTraining = [day(mon, planned: true, done: true), day(mon.add(const Duration(days: 1)))];
      expect(Gamification.weeklyScore(onlyTraining).total, closeTo(50, 1e-9));
    });

    test('with no planned day yet only food counts (weights renormalised)', () {
      final days = [day(mon, logged: true, kcal: 2100), day(mon.add(const Duration(days: 1)), logged: true, kcal: 1950)];
      final s = Gamification.weeklyScore(days);
      expect(s.training, isNull);
      expect(s.total, closeTo(100, 1e-9));
    });

    test('extra workouts cannot push training above 100%', () {
      final days = [day(mon, planned: true, done: true), day(mon.add(const Duration(days: 1)), done: true), day(mon.add(const Duration(days: 2)), done: true)];
      expect(Gamification.weeklyScore(days).training, 1.0);
    });

    test('calorie tolerance is ±15%', () {
      expect(DayRecord(date: mon, foodLogged: true, kcal: 2300, targetKcal: 2000).withinTarget, isTrue);
      expect(DayRecord(date: mon, foodLogged: true, kcal: 2301, targetKcal: 2000).withinTarget, isFalse);
      expect(DayRecord(date: mon, foodLogged: true, kcal: 1700, targetKcal: 2000).withinTarget, isTrue);
      expect(DayRecord(date: mon, foodLogged: true, kcal: 1699, targetKcal: 2000).withinTarget, isFalse);
      expect(DayRecord(date: mon, foodLogged: false).withinTarget, isFalse);
    });

    test('scores are always within 0..100 and weeklyScores ignores future days', () {
      final days = [for (var i = 0; i < 10; i++) day(mon.add(Duration(days: i)), planned: true, done: true, logged: true)];
      final scores = Gamification.weeklyScores(days, mon.add(const Duration(days: 8)));
      expect(scores.length, 2);
      for (final s in scores) {
        expect(s.total, inInclusiveRange(0, 100));
      }
      expect(scores.last.daysElapsed, 2); // Mon, Tue of the second week only
    });
  });

  group('levels', () {
    test('thresholds', () {
      expect(Gamification.levelForScore(0), FitnessLevel.beginner);
      expect(Gamification.levelForScore(39.9), FitnessLevel.beginner);
      expect(Gamification.levelForScore(40), FitnessLevel.intermediate);
      expect(Gamification.levelForScore(69.9), FitnessLevel.intermediate);
      expect(Gamification.levelForScore(70), FitnessLevel.advanced);
    });
    test('weeks with no activity are ignored and no data means beginner', () {
      const quiet = FitnessScore.empty;
      expect(Gamification.levelFromScores([quiet, quiet]), FitnessLevel.beginner);
      final good = FitnessScore(total: 80, training: 1, logging: 1, adherence: 1, workoutsDone: 3, workoutsPlanned: 3, daysLogged: 7, daysOnTarget: 7, daysElapsed: 7);
      expect(Gamification.levelFromScores([quiet, good]), FitnessLevel.advanced);
    });
  });

  group('streaks and badges', () {
    final today = DateTime(2026, 10, 14); // Wednesday

    test('rest days do not break a workout streak, a missed planned day does', () {
      // Fri done, Sat rest, Sun rest, Mon done, Tue missed, Wed (today) not yet done
      final d = [
        day(DateTime(2026, 10, 9), planned: true, done: true),
        day(DateTime(2026, 10, 10)),
        day(DateTime(2026, 10, 11)),
        day(DateTime(2026, 10, 12), planned: true, done: true),
        day(DateTime(2026, 10, 13), planned: true),
        day(today, planned: true),
      ];
      expect(Gamification.workoutStreak(d), 0);
      final ok = [...d.sublist(0, 4), day(DateTime(2026, 10, 13), planned: true, done: true), day(today, planned: true)];
      expect(Gamification.workoutStreak(ok), 3);
      expect(Gamification.bestWorkoutStreak(d), 2); // Fri and Mon: the weekend rest days do not break it
    });

    test('logging streak ignores a not-yet-logged today', () {
      final d = [day(DateTime(2026, 10, 12), logged: true), day(DateTime(2026, 10, 13), logged: true), day(today)];
      expect(Gamification.loggingStreak(d), 2);
      expect(Gamification.loggingStreak([day(DateTime(2026, 10, 12)), day(DateTime(2026, 10, 13), logged: true), day(today, logged: true)]), 2);
    });

    test('badges are earned by the stated rules and not before', () {
      final empty = [for (final x in daysEnding(today, 7)) day(x)];
      expect(Gamification.earnedBadgeIds(empty, today), isEmpty);

      final one = [for (final x in daysEnding(today, 7)) day(x, planned: true, done: x == today)];
      expect(Gamification.earnedBadgeIds(one, today), {'first_workout'});

      final week = [for (final x in daysEnding(DateTime(2026, 10, 18), 7)) day(x, planned: true, done: true, logged: true)];
      final ids = Gamification.earnedBadgeIds(week, DateTime(2026, 10, 18));
      expect(ids, containsAll(['first_workout', 'streak_3', 'streak_7', 'full_week', 'logger_3', 'logger_7', 'on_target_3', 'high_scorer']));
    });

    test('catalogue marks earned badges and keeps stored history', () {
      final list = Gamification.badges({'streak_3'});
      expect(list.where((b) => b.earned).map((b) => b.id), ['streak_3']);
      expect(list.length, Gamification.catalogue.length);
      expect({for (final b in Gamification.catalogue) b.id}.length, Gamification.catalogue.length); // unique ids
      for (final b in Gamification.catalogue) {
        expect(RegExp(r'^[a-z0-9_]{1,30}$').hasMatch(b.id), isTrue); // must satisfy the database rule for badge ids
      }
    });
  });

  group('K-Means', () {
    List<List<double>> blobs() => [
          for (var i = 0; i < 6; i++) [0.1 + i * 0.01, 0.1, 0.1],
          for (var i = 0; i < 6; i++) [0.5 + i * 0.01, 0.5, 0.5],
          for (var i = 0; i < 6; i++) [0.9 + i * 0.01, 0.9, 0.9],
        ];

    test('separates three clear groups and is deterministic', () {
      final a = kMeans(blobs(), 3);
      final b = kMeans(blobs(), 3);
      expect(a.assignments, b.assignments);
      for (final g in [0, 6, 12]) {
        expect({for (var i = g; i < g + 6; i++) a.assignments[i]}.length, 1);
      }
      expect({a.assignments[0], a.assignments[6], a.assignments[12]}.length, 3);
    });

    test('needs at least k points', () {
      expect(() => kMeans([[1.0], [2.0]], 3), throwsArgumentError);
    });

    test('small cohorts use the score thresholds and say so', () {
      final r = groupCohort([const CohortMember('a', 10, 0, 1), const CohortMember('b', 55, 3, 5), const CohortMember('c', 90, 5, 7)]);
      expect(r.levels, {'a': FitnessLevel.beginner, 'b': FitnessLevel.intermediate, 'c': FitnessLevel.advanced});
      expect(r.method, contains('thresholds'));
    });

    test('a cohort of 15+ is grouped by K-Means, ordered by average score', () {
      final members = [
        for (var i = 0; i < 6; i++) CohortMember('low$i', 10 + i.toDouble(), 0, 1),
        for (var i = 0; i < 6; i++) CohortMember('mid$i', 50 + i.toDouble(), 3, 4),
        for (var i = 0; i < 6; i++) CohortMember('high$i', 90 + i.toDouble(), 6, 7),
      ];
      final r = groupCohort(members);
      expect(r.method, startsWith('K-Means'));
      expect(r.levels['low0'], FitnessLevel.beginner);
      expect(r.levels['mid3'], FitnessLevel.intermediate);
      expect(r.levels['high5'], FitnessLevel.advanced);
    });
  });

  group('inactivity (FR-5)', () {
    final planned = {1, 3, 5}; // Mon, Wed, Fri

    test('rest days alone are not inactivity', () {
      // last workout Fri 9 Oct, today Mon 12 Oct: Sat and Sun were rest days
      expect(detectInactivity(today: DateTime(2026, 10, 12), lastWorkout: DateTime(2026, 10, 9), plannedWeekdays: planned), isNull);
    });
    test('missed planned days over three or more days are inactivity', () {
      final r = detectInactivity(today: DateTime(2026, 10, 14), lastWorkout: DateTime(2026, 10, 9), plannedWeekdays: planned);
      expect(r, isNotNull);
      expect(r!.daysSinceWorkout, 5);
      expect(r.missedPlannedDays, 1); // Monday; today (Wednesday) does not count yet
    });
    test('recent activity and no history give no alert', () {
      expect(detectInactivity(today: DateTime(2026, 10, 14), lastWorkout: DateTime(2026, 10, 13), plannedWeekdays: planned), isNull);
      expect(detectInactivity(today: DateTime(2026, 10, 14), lastWorkout: null, plannedWeekdays: planned), isNull);
    });
  });

  group('reminder times (FR-3)', () {
    test('next occurrence of a weekday', () {
      final now = DateTime(2026, 10, 14, 10, 0); // Wednesday
      expect(nextWeekdayAt(now, DateTime.wednesday, 18, 30), DateTime(2026, 10, 14, 18, 30));
      expect(nextWeekdayAt(now, DateTime.wednesday, 9, 0), DateTime(2026, 10, 21, 9, 0)); // already passed today
      expect(nextWeekdayAt(now, DateTime.monday, 7, 0), DateTime(2026, 10, 19, 7, 0));
      expect(nextWeekdayAt(now, DateTime.sunday, 7, 0).weekday, DateTime.sunday);
    });
    test('inactivity nudge is sent once, never in the past', () {
      final now = DateTime(2026, 10, 14, 10, 0);
      expect(inactivityNudgeAt(now, null), isNull);
      expect(inactivityNudgeAt(now, DateTime(2026, 10, 13)), DateTime(2026, 10, 16, 18)); // 3 days after
      expect(inactivityNudgeAt(now, DateTime(2026, 10, 1)), DateTime(2026, 10, 15, 18)); // overdue -> tomorrow
    });
  });

  group('roles (FR-2)', () {
    test('unknown or missing roles are plain members', () {
      expect(UserRoleRules.parse(null), UserRole.user);
      expect(UserRoleRules.parse('superuser'), UserRole.user);
      expect(UserRoleRules.parse('doctor'), UserRole.doctor);
    });
    test('permissions', () {
      expect(UserRole.user.can(Permission.viewOwnData), isTrue);
      expect(UserRole.user.can(Permission.viewAssignedPatientData), isFalse);
      expect(UserRole.doctor.can(Permission.uploadPrescriptions), isTrue);
      expect(UserRole.trainer.can(Permission.uploadPrescriptions), isFalse);
      expect(UserRole.nutritionist.can(Permission.editAssignedPlans), isTrue);
      expect(UserRole.admin.can(Permission.manageAccounts), isTrue);
      expect(UserRole.admin.can(Permission.viewAssignedPatientData), isFalse); // administrators manage accounts, they do not read health data
    });
  });
}
