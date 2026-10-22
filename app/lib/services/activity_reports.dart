import 'activity_service.dart';
import 'calorie_optimizer.dart';
import 'food_log_service.dart';
import 'gamification.dart';
import 'workout_session/workout_log_service.dart';

/// Module 17 (Analytics & Progress Dashboard): the figures behind the Weekly Report (FR-7, and the weekly and monthly analytics of FE-10)
/// and the Workout History (FR-9). Pure functions over what the app already stores: no database, no clock of their own.

/// A span of whole days, [start] and [end] both included.
class ReportPeriod {
  final DateTime start;
  final DateTime end;
  final String label;
  const ReportPeriod(this.start, this.end, this.label);

  /// The Monday-to-Sunday week that holds [day].
  factory ReportPeriod.weekOf(DateTime day, {String? label}) {
    final s = Gamification.weekStart(day);
    return ReportPeriod(s, s.add(const Duration(days: 6)), label ?? 'Week of ${_short(s)}');
  }

  /// The [n] days ending on [last].
  factory ReportPeriod.lastDays(int n, DateTime last, {String? label}) {
    final e = Gamification.dateOnly(last);
    return ReportPeriod(e.subtract(Duration(days: n - 1)), e, label ?? 'Last $n days');
  }

  int get days => end.difference(start).inDays + 1;
  bool contains(DateTime d) {
    final x = Gamification.dateOnly(d);
    return !x.isBefore(start) && !x.isAfter(end);
  }

  static String _short(DateTime d) => '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';
}

/// The numbers and the written summary for one [ReportPeriod].
class PeriodReport {
  final ReportPeriod period;

  /// Days of the period that have already happened (today included), which is what the figures are counted over.
  final int daysElapsed;
  final int workoutsDone;
  final int workoutsPlanned;
  final int activeMinutes;
  final int kcalBurned;
  final int sessions;
  final int exercisesDone;
  final int daysLogged;
  final int daysOnTarget;
  final double? avgKcal;
  final int? targetKcal;

  /// Average form score over the camera sessions of the period (null when there were none with a score).
  final double? avgPosture;
  final int postureSessions;
  final double? weightStartKg;
  final double? weightEndKg;

  /// The fitness score (0 to 100) when the period is one week; null otherwise.
  final double? score;
  final double? previousScore;
  final List<String> summary;
  final String focus;

  const PeriodReport({
    required this.period,
    required this.daysElapsed,
    required this.workoutsDone,
    required this.workoutsPlanned,
    required this.activeMinutes,
    required this.kcalBurned,
    required this.sessions,
    required this.exercisesDone,
    required this.daysLogged,
    required this.daysOnTarget,
    required this.avgKcal,
    required this.targetKcal,
    required this.avgPosture,
    required this.postureSessions,
    required this.weightStartKg,
    required this.weightEndKg,
    required this.score,
    required this.previousScore,
    required this.summary,
    required this.focus,
  });

  double? get weightChangeKg => weightStartKg == null || weightEndKg == null ? null : weightEndKg! - weightStartKg!;
}

/// One day's workouts for the history list.
class HistoryDay {
  final DateTime date;
  final int minutes;
  final int kcal;
  final List<WorkoutLogEntry> entries;
  const HistoryDay({required this.date, required this.minutes, required this.kcal, required this.entries});

  double? get avgPosture {
    final p = [for (final e in entries) if (e.postureScore != null) e.postureScore!];
    return p.isEmpty ? null : p.reduce((a, b) => a + b) / p.length;
  }
}

/// One square of the calendar heatmap.
class HeatCell {
  final DateTime date;

  /// 0 = no workout, 1 to 4 = from a short to a long one (see [ActivityReports.intensityFor]); the day is in the future when [future].
  final int level;
  final int minutes;
  final bool future;
  const HeatCell(this.date, this.level, this.minutes, {this.future = false});
}

class ActivityReports {
  ActivityReports._();

  /// Heatmap shades: under 20 minutes, under 40, under 60, 60 or more. A day with a workout but no minutes recorded still gets level 1.
  static int intensityFor(int minutes, {required bool done}) {
    if (!done && minutes <= 0) return 0;
    if (minutes < 20) return 1;
    if (minutes < 40) return 2;
    if (minutes < 60) return 3;
    return 4;
  }

  static DateTime _d(DateTime d) => Gamification.dateOnly(d);

  /// [activity] and [kcalByDate] are keyed by `YYYY-MM-DD`. [today] decides which days of the period have happened.
  static PeriodReport build({
    required ReportPeriod period,
    required DateTime today,
    required Map<String, ActivityEntry> activity,
    required Map<String, double> kcalByDate,
    required Set<int> plannedWeekdays,
    required int? targetKcal,
    List<WorkoutLogEntry> sessions = const [],
    List<WeightPoint> weights = const [],
    double? previousScore,
  }) {
    final t = _d(today);
    final days = <DayRecord>[];
    for (var i = 0; i < period.days; i++) {
      final d = period.start.add(Duration(days: i));
      if (d.isAfter(t)) break;
      final key = FoodLogService.dateKey(d);
      final act = activity[key];
      final kcal = kcalByDate[key];
      days.add(DayRecord(date: d, planned: plannedWeekdays.contains(d.weekday), workoutDone: act != null, minutes: act?.minutes ?? 0, foodLogged: kcal != null, kcal: kcal, targetKcal: targetKcal));
    }
    final inPeriod = [for (final s in sessions) if (period.contains(s.endedAt)) s];
    final done = days.where((d) => d.workoutDone).length;
    final planned = days.where((d) => d.planned).length;
    final logged = days.where((d) => d.foodLogged).toList();
    final onTarget = logged.where((d) => d.withinTarget).length;
    final avgKcal = logged.isEmpty ? null : logged.fold(0.0, (s, d) => s + d.kcal!) / logged.length;
    final posture = [for (final s in inPeriod) if (s.postureScore != null) s.postureScore!];
    final w = [for (final p in weights) if (period.contains(p.date)) p]..sort((a, b) => a.date.compareTo(b.date));
    final isWeek = period.days == 7 && period.start.weekday == DateTime.monday;
    final score = isWeek && days.isNotEmpty ? Gamification.weeklyScore(days).total : null;
    var kcalBurned = 0;
    for (final d in days) {
      kcalBurned += activity[FoodLogService.dateKey(d.date)]?.kcal ?? 0;
    }

    final report = PeriodReport(
      period: period,
      daysElapsed: days.length,
      workoutsDone: done,
      workoutsPlanned: planned,
      activeMinutes: days.fold(0, (s, d) => s + d.minutes),
      kcalBurned: kcalBurned,
      sessions: inPeriod.length,
      exercisesDone: inPeriod.map((s) => s.exerciseId).toSet().length,
      daysLogged: logged.length,
      daysOnTarget: onTarget,
      avgKcal: avgKcal,
      targetKcal: targetKcal,
      avgPosture: posture.isEmpty ? null : posture.reduce((a, b) => a + b) / posture.length,
      postureSessions: posture.length,
      weightStartKg: w.length >= 2 ? w.first.kg : null,
      weightEndKg: w.length >= 2 ? w.last.kg : null,
      score: score,
      previousScore: previousScore,
      summary: const [],
      focus: '',
    );
    return _withSummary(report);
  }

  /// The written summary. It is produced by rules from the user's own numbers (not by an AI model), and says nothing the numbers do not
  /// support. It never praises eating far below the calorie target.
  static PeriodReport _withSummary(PeriodReport r) {
    final lines = <String>[];
    final span = r.period.days == 7 ? 'this week' : 'in this period';
    if (r.daysElapsed == 0) {
      lines.add('This period has not started yet.');
    } else {
      if (r.workoutsPlanned > 0) {
        final extra = r.workoutsDone > r.workoutsPlanned ? ' (${r.workoutsDone - r.workoutsPlanned} more than planned)' : '';
        lines.add(r.workoutsDone == 0
            ? 'You have not logged a workout $span; ${r.workoutsPlanned} were planned.'
            : 'You completed ${r.workoutsDone} of ${r.workoutsPlanned} planned workouts $span$extra, ${r.activeMinutes} active minutes in all.');
      } else if (r.workoutsDone > 0) {
        lines.add('You did ${r.workoutsDone} workout${r.workoutsDone == 1 ? '' : 's'} $span, ${r.activeMinutes} active minutes in all.');
      } else {
        lines.add('No workouts were logged $span.');
      }
      if (r.daysLogged == 0) {
        lines.add('You did not log any meals $span, so there is nothing to compare with your calorie target.');
      } else {
        final avg = r.avgKcal!.round();
        var t = 'You logged meals on ${r.daysLogged} of ${r.daysElapsed} days, averaging $avg kcal a day';
        final target = r.targetKcal;
        if (target != null && target > 0) {
          final ratio = r.avgKcal! / target;
          if (ratio < 0.7) {
            t += ', well below your target of $target kcal. Eating much less than planned is not a safe way to lose weight; if this is not just missed logging, raise it with a doctor or dietitian';
          } else if (ratio < 0.85) {
            t += ', below your target of $target kcal';
          } else if (ratio <= 1.15) {
            t += ', close to your target of $target kcal';
          } else {
            t += ', above your target of $target kcal';
          }
        }
        lines.add('$t.');
      }
      if (r.score != null) {
        final prev = r.previousScore;
        var t = 'Your fitness score was ${r.score!.round()} out of 100';
        if (prev != null) {
          final diff = (r.score! - prev).round();
          t += diff == 0 ? ', the same as the week before' : (diff > 0 ? ', up $diff from the week before' : ', down ${-diff} from the week before');
        }
        lines.add('$t.');
      }
      if (r.avgPosture != null) {
        lines.add('Your form score averaged ${r.avgPosture!.round()}% over ${r.postureSessions} camera session${r.postureSessions == 1 ? '' : 's'}.');
      }
      final ch = r.weightChangeKg;
      if (ch != null) {
        lines.add(ch.abs() < 0.05 ? 'Your weight stayed at ${r.weightEndKg!.toStringAsFixed(1)} kg.' : 'Your weight went from ${r.weightStartKg!.toStringAsFixed(1)} to ${r.weightEndKg!.toStringAsFixed(1)} kg (${ch > 0 ? '+' : '-'}${ch.abs().toStringAsFixed(1)} kg).');
      }
    }
    return PeriodReport(
      period: r.period, daysElapsed: r.daysElapsed, workoutsDone: r.workoutsDone, workoutsPlanned: r.workoutsPlanned, activeMinutes: r.activeMinutes, kcalBurned: r.kcalBurned,
      sessions: r.sessions, exercisesDone: r.exercisesDone, daysLogged: r.daysLogged, daysOnTarget: r.daysOnTarget, avgKcal: r.avgKcal, targetKcal: r.targetKcal,
      avgPosture: r.avgPosture, postureSessions: r.postureSessions, weightStartKg: r.weightStartKg, weightEndKg: r.weightEndKg, score: r.score, previousScore: r.previousScore,
      summary: lines,
      focus: _focus(r),
    );
  }

  /// One thing to work on, chosen from the weakest part of the period.
  static String _focus(PeriodReport r) {
    if (r.daysElapsed == 0) return 'Come back once the period has started.';
    final training = r.workoutsPlanned == 0 ? 1.0 : r.workoutsDone / r.workoutsPlanned;
    final logging = r.daysLogged / r.daysElapsed;
    if (r.workoutsPlanned > 0 && training < 0.5) return 'Focus: get to at least half of your planned workouts. Start with the next planned day and do just the warm-up and one exercise.';
    if (logging < 0.5) return 'Focus: log your meals on more days. Even a rough entry makes the calorie picture useful.';
    if (r.daysLogged >= 3 && r.daysOnTarget / r.daysLogged < 0.5 && r.targetKcal != null) return 'Focus: bring your meals closer to your calorie target on more of the days you log.';
    if (r.avgPosture != null && r.avgPosture! < 70) return 'Focus: form. Slow the repetitions down and follow the on-screen corrections.';
    return 'Focus: keep the same rhythm. Your training and logging are on track.';
  }

  /// Heatmap of the last [weeks] weeks ending with the week of [today], one list per week (Monday to Sunday, oldest week first).
  static List<List<HeatCell>> heatmap({required DateTime today, required Map<String, ActivityEntry> activity, int weeks = 12}) {
    final t = _d(today);
    final firstMonday = Gamification.weekStart(t).subtract(Duration(days: 7 * (weeks - 1)));
    return [
      for (var w = 0; w < weeks; w++)
        [
          for (var i = 0; i < 7; i++)
            () {
              final d = firstMonday.add(Duration(days: w * 7 + i));
              final act = activity[FoodLogService.dateKey(d)];
              final future = d.isAfter(t);
              return HeatCell(d, future ? 0 : intensityFor(act?.minutes ?? 0, done: act != null), act?.minutes ?? 0, future: future);
            }(),
        ],
    ];
  }

  /// The days with a workout between [from] and [to], newest first, each with its sessions. A day recorded only as "workout done"
  /// (no session detail) is still listed, with no entries.
  static List<HistoryDay> history({required DateTime from, required DateTime to, required Map<String, ActivityEntry> activity, required List<WorkoutLogEntry> sessions}) {
    final f = _d(from), t = _d(to);
    final byDay = <String, List<WorkoutLogEntry>>{};
    for (final s in sessions) {
      final d = _d(s.endedAt);
      if (d.isBefore(f) || d.isAfter(t)) continue;
      byDay.putIfAbsent(FoodLogService.dateKey(d), () => []).add(s);
    }
    final keys = {...byDay.keys, for (final e in activity.entries) if (!(DateTime.tryParse(e.key) ?? f.subtract(const Duration(days: 1))).isBefore(f) && !(DateTime.tryParse(e.key) ?? t.add(const Duration(days: 1))).isAfter(t)) e.key};
    final out = [
      for (final k in keys)
        () {
          final entries = (byDay[k] ?? [])..sort((a, b) => a.endedAt.compareTo(b.endedAt));
          final act = activity[k];
          final fromSessions = entries.fold<int>(0, (s, e) => s + (e.duration.inSeconds / 60).round());
          return HistoryDay(date: DateTime.parse(k), minutes: act?.minutes ?? fromSessions, kcal: act?.kcal ?? 0, entries: entries);
        }(),
    ]..sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  /// Total minutes and workout days in a list of history days.
  static (int days, int minutes) totals(List<HistoryDay> days) => (days.length, days.fold(0, (s, d) => s + d.minutes));
}
