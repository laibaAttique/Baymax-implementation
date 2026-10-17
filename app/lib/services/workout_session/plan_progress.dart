import 'package:flutter/foundation.dart';

import '../../models/plan.dart';
import '../../models/workout_session.dart';
import '../activity_service.dart';
import '../food_log_service.dart';
import '../user_session.dart';
import 'workout_log_service.dart';

/// Module 4 ↔ Module 5: which planned exercises have been completed through a session (camera or manual).
///
/// * A planned exercise counts as done only when a session linked to it reached its target ([SessionSummary.completedTarget]);
///   opening the camera, skipping or stopping early never completes it.
/// * Progress is keyed by plan fingerprint + plan day + calendar date, so a regenerated plan starts fresh and repeated
///   sessions for the same entry do not create anything twice (it is a set).
/// * When every main exercise of TODAY's plan day is done, the day is marked done through [ActivityService.markDone] —
///   the same record the Workout tab's "Mark done" writes and the fitness score, streaks, badges and analytics read.
/// * Sessions from the generic exercise library have no plan link and stay independent workouts.
class PlanProgress extends ChangeNotifier {
  PlanProgress({
    WorkoutLogStore? store,
    PersonalizedPlan? Function()? currentPlan,
    String? Function()? currentPlanId,
    double Function()? weightKg,
    Future<void> Function(DateTime date, WorkoutDay day, double weightKg)? markDay,
    DateTime Function()? now,
  })  : _store = store,
        _currentPlan = currentPlan ?? (() => UserSession.instance.plan),
        _currentPlanId = currentPlanId ?? (() => UserSession.instance.planId),
        _weightKg = weightKg ?? (() => UserSession.instance.profile?.weightKg ?? 0),
        _markDay = markDay ?? ((date, day, kg) => ActivityService.instance.markDone(date, minutes: day.durationMin, kcal: day.kcal(kg))),
        _now = now ?? DateTime.now;

  static final PlanProgress instance = PlanProgress(store: FirebaseWorkoutLog.instance);

  final WorkoutLogStore? _store;
  final PersonalizedPlan? Function() _currentPlan;
  final String? Function() _currentPlanId;
  final double Function() _weightKg;
  final Future<void> Function(DateTime date, WorkoutDay day, double weightKg) _markDay;
  final DateTime Function() _now;

  final Map<String, Set<int>> _done = {};
  final Set<String> _daysMarked = {};
  String? _loadedFor;

  static String _key(String planId, int weekday, String date) => '$planId|$weekday|$date';
  static String dateKey(DateTime d) => FoodLogService.dateKey(d);

  /// 0 = Monday.
  int get todayIndex => _now().weekday - 1;
  String get todayKey => dateKey(_now());

  /// The link for entry [entryIndex] of plan day [weekday], done today. Null without a plan.
  PlanLink? linkFor(int weekday, int entryIndex) {
    final id = _currentPlanId();
    if (id == null) return null;
    return PlanLink(planId: id, weekday: weekday, entryIndex: entryIndex, date: todayKey);
  }

  /// Planned entries of [weekday] completed today in the current plan.
  Set<int> completedToday(int weekday) {
    final id = _currentPlanId();
    if (id == null) return const {};
    return _done[_key(id, weekday, todayKey)] ?? const {};
  }

  bool isDoneToday(int weekday, int entryIndex) => completedToday(weekday).contains(entryIndex);

  /// The entries that make a day complete: everything except warm-up, cool-down, stretches and balance work.
  static List<int> mainEntries(WorkoutDay day) => [
        for (var i = 0; i < day.exercises.length; i++)
          if (day.exercises[i].exercise.group != 'mobility') i,
      ];

  /// Reads today's linked sessions back from the database (after a restart). Safe to call repeatedly.
  Future<void> loadToday() async {
    final id = _currentPlanId();
    final store = _store;
    if (id == null || store == null) return;
    final marker = '$id|$todayKey';
    if (_loadedFor == marker) return;
    try {
      final now = _now();
      final sessions = await store.since(DateTime(now.year, now.month, now.day));
      var changed = false;
      for (final s in sessions) {
        if (s.planId == id && s.planDate == todayKey && s.planCompleted && s.planWeekday != null && s.planEntry != null) {
          changed |= (_done[_key(id, s.planWeekday!, todayKey)] ??= {}).add(s.planEntry!);
        }
      }
      _loadedFor = marker;
      if (changed) notifyListeners();
    } catch (_) {
      // Offline or not signed in: progress from this app run still shows.
    }
  }

  /// Called for every finished session.
  Future<void> record(SessionSummary s) async {
    final link = s.plan;
    if (link == null || !s.completedTarget) return;
    final added = (_done[_key(link.planId, link.weekday, link.date)] ??= {}).add(link.entryIndex);
    if (added) notifyListeners();
    await _markDayIfComplete(link);
  }

  Future<void> _markDayIfComplete(PlanLink link) async {
    if (link.date != todayKey || link.weekday != todayIndex) return; // only today's plan day completes today
    if (link.planId != _currentPlanId()) return;
    final day = _currentPlan()?.week[link.weekday];
    if (day == null) return;
    final done = _done[_key(link.planId, link.weekday, link.date)] ?? const {};
    final main = mainEntries(day);
    if (main.isEmpty || !main.every(done.contains)) return;
    final marker = _key(link.planId, link.weekday, link.date);
    if (!_daysMarked.add(marker)) return;
    try {
      await _markDay(_now(), day, _weightKg());
      notifyListeners();
    } catch (_) {
      _daysMarked.remove(marker); // try again on the next completed session
    }
  }

  /// Whether today's plan day was completed through sessions in this run.
  bool dayMarkedToday(int weekday) {
    final id = _currentPlanId();
    return id != null && _daysMarked.contains(_key(id, weekday, todayKey));
  }

  @visibleForTesting
  void reset() {
    _done.clear();
    _daysMarked.clear();
    _loadedFor = null;
  }
}
