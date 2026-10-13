import '../models/plan.dart';
import 'activity_service.dart';
import 'food_log_service.dart';
import 'gamification.dart';
import 'realtime_db.dart';

/// Everything Module 11 shows about the user's recent activity, computed from the last 28 days.
class ProgressSnapshot {
  static const windowDays = 28;

  final DateTime today;
  final List<DayRecord> days; // oldest -> newest, the last day is today
  final FitnessScore week; // the current Monday-based week up to today
  final List<FitnessScore> weeks; // oldest -> newest
  final FitnessLevel level;
  final int workoutStreak;
  final int loggingStreak;
  final DateTime? lastWorkout;
  final Inactivity? inactivity;

  /// Badges earned according to the last 28 days.
  final Set<String> earnedNow;

  /// Badges earned now or stored from earlier (badges are never taken away).
  final Set<String> earned;

  /// Badges that were not stored before this load.
  final Set<String> newBadges;

  const ProgressSnapshot({
    required this.today,
    required this.days,
    required this.week,
    required this.weeks,
    required this.level,
    required this.workoutStreak,
    required this.loggingStreak,
    required this.lastWorkout,
    required this.inactivity,
    required this.earnedNow,
    required this.earned,
    required this.newBadges,
  });

  List<AppBadge> get badges => Gamification.badges(earned);

  /// Pure computation (no database): [activity] and [kcalByDate] are keyed by `YYYY-MM-DD`.
  factory ProgressSnapshot.build({
    required DateTime today,
    required Set<int> plannedWeekdays,
    required int? targetKcal,
    required Map<String, ActivityEntry> activity,
    required Map<String, double> kcalByDate,
    DateTime? lastWorkout,
    Set<String> storedBadges = const {},
  }) {
    final t = Gamification.dateOnly(today);
    final days = <DayRecord>[
      for (var i = windowDays - 1; i >= 0; i--)
        () {
          final d = t.subtract(Duration(days: i));
          final key = FoodLogService.dateKey(d);
          final act = activity[key];
          final kcal = kcalByDate[key];
          return DayRecord(
            date: d,
            planned: plannedWeekdays.contains(d.weekday),
            workoutDone: act != null,
            minutes: act?.minutes ?? 0,
            foodLogged: kcal != null,
            kcal: kcal,
            targetKcal: targetKcal,
          );
        }(),
    ];
    final weeks = Gamification.weeklyScores(days, t);
    final currentWeekStart = Gamification.weekStart(t);
    final thisWeek = Gamification.weeklyScore(days.where((d) => !d.date.isBefore(currentWeekStart)).toList());
    var last = lastWorkout;
    for (final d in days) {
      if (d.workoutDone && (last == null || d.date.isAfter(last))) last = d.date;
    }
    final earnedNow = Gamification.earnedBadgeIds(days, t);
    return ProgressSnapshot(
      today: t,
      days: days,
      week: thisWeek,
      weeks: weeks,
      level: Gamification.levelFromScores(weeks),
      workoutStreak: Gamification.workoutStreak(days),
      loggingStreak: Gamification.loggingStreak(days),
      lastWorkout: last,
      inactivity: detectInactivity(today: t, lastWorkout: last, plannedWeekdays: plannedWeekdays),
      earnedNow: earnedNow,
      earned: {...storedBadges, ...earnedNow},
      newBadges: earnedNow.difference(storedBadges),
    );
  }
}

/// Loads the activity and food logs and the stored badges, and builds the [ProgressSnapshot].
class ProgressService {
  ProgressService._();
  static final ProgressService instance = ProgressService._();

  static Set<int> plannedWeekdays(PersonalizedPlan plan) => {
        for (var i = 0; i < 7; i++)
          if (plan.week[i] != null) i + 1
      };

  Future<ProgressSnapshot> load(PersonalizedPlan plan, {DateTime? today}) async {
    final t = Gamification.dateOnly(today ?? DateTime.now());
    final from = FoodLogService.dateKey(t.subtract(const Duration(days: ProgressSnapshot.windowDays - 1)));
    final to = FoodLogService.dateKey(t);
    final results = await Future.wait([
      ActivityService.instance.range(from, to),
      FoodLogService.instance.kcalByDate(from, to),
      ActivityService.instance.lastWorkoutDate(),
      _storedBadges(),
    ]);
    final snapshot = ProgressSnapshot.build(
      today: t,
      plannedWeekdays: plannedWeekdays(plan),
      targetKcal: plan.nutrition.targetKcal,
      activity: results[0] as Map<String, ActivityEntry>,
      kcalByDate: results[1] as Map<String, double>,
      lastWorkout: results[2] as DateTime?,
      storedBadges: results[3] as Set<String>,
    );
    if (snapshot.newBadges.isNotEmpty) {
      try {
        await _award(snapshot.newBadges);
      } catch (_) {
        // Not stored this time; they are earned again on the next load.
      }
    }
    return snapshot;
  }

  Future<Set<String>> _storedBadges() {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('badges').get();
      if (!snap.exists) return <String>{};
      return (RealtimeDb.plain(snap.value) as Map<String, dynamic>).keys.toSet();
    });
  }

  Future<void> _award(Set<String> ids) {
    return RealtimeDb.guard(() async {
      final uid = RealtimeDb.uid;
      await RealtimeDb.db.ref().update({for (final id in ids) 'users/$uid/badges/$id': DateTime.now().millisecondsSinceEpoch});
    });
  }
}
