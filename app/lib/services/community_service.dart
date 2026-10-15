import 'dart:math';
import 'gamification.dart';
import 'progress_service.dart';
import 'realtime_db.dart';

class LeaderboardEntry {
  final String uid;
  final String name;
  final double score;
  final int workouts;
  final int logDays;
  const LeaderboardEntry(this.uid, this.name, this.score, this.workouts, this.logDays);
}

/// Module 11 (FR-2): the weekly leaderboard at `leaderboard/{YYYY-Www}/{uid}`.
///
/// Taking part is opt-in. An entry holds only the display name the user chose, the week's score and two small counts.
/// Scores are calculated on the phone, so a modified app could submit a false score; a trustworthy leaderboard needs the
/// score computed on a server, which this version does not have.
class CommunityService {
  CommunityService._();
  static final CommunityService instance = CommunityService._();

  static String weekId(DateTime day) => Gamification.isoWeekId(day);

  /// Week number for display ("Week 42"), from ids like `2026-W42`.
  static int weekNumber(DateTime day) => int.parse(weekId(day).split('-W').last);

  /// When the weekly leaderboard resets: the next Monday at 00:00 (local time), the start of the next ISO week.
  static DateTime nextReset(DateTime now) => Gamification.weekStart(now).add(const Duration(days: 7));

  /// "Resets in 3d 5h", "Resets in 5h 20m" or "Resets in 12m".
  static String resetsIn(DateTime now) {
    final left = nextReset(now).difference(now);
    if (left.inDays >= 1) return 'Resets in ${left.inDays}d ${left.inHours % 24}h';
    if (left.inHours >= 1) return 'Resets in ${left.inHours}h ${left.inMinutes % 60}m';
    return 'Resets in ${left.inMinutes.clamp(1, 59)}m';
  }

  /// Writes (or updates) the user's entry for the current week.
  Future<void> publish(ProgressSnapshot progress, String displayName) {
    return RealtimeDb.guard(() async {
      final name = displayName.trim().isEmpty ? 'Member' : displayName.trim();
      await RealtimeDb.db.ref('leaderboard/${weekId(progress.today)}/${RealtimeDb.uid}').set({
        'name': name.substring(0, min(name.length, 30)),
        'score': double.parse(progress.week.total.toStringAsFixed(1)),
        'workouts': progress.week.workoutsDone.clamp(0, 7),
        'logDays': progress.week.daysLogged.clamp(0, 7),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  /// Removes the user's entry for the current week (when they opt out).
  Future<void> withdraw(DateTime today) {
    return RealtimeDb.guard(() => RealtimeDb.db.ref('leaderboard/${weekId(today)}/${RealtimeDb.uid}').remove());
  }

  /// The best [limit] entries of the week, highest score first.
  Future<List<LeaderboardEntry>> top(DateTime today, {int limit = 50}) {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.db.ref('leaderboard/${weekId(today)}').orderByChild('score').limitToLast(limit).get();
      if (!snap.exists) return <LeaderboardEntry>[];
      final map = RealtimeDb.plain(snap.value) as Map<String, dynamic>;
      final list = [
        for (final e in map.entries)
          LeaderboardEntry(
            e.key,
            ((e.value as Map)['name'] as String?) ?? 'Member',
            (((e.value as Map)['score'] as num?) ?? 0).toDouble(),
            (((e.value as Map)['workouts'] as num?) ?? 0).toInt(),
            (((e.value as Map)['logDays'] as num?) ?? 0).toInt(),
          ),
      ]..sort((a, b) => b.score.compareTo(a.score));
      return list;
    });
  }

  /// Level of each participant, grouped with K-Means when enough people take part (FR-4, FE-5).
  CohortLevels levels(List<LeaderboardEntry> entries) =>
      groupCohort([for (final e in entries) CohortMember(e.uid, e.score, e.workouts, e.logDays)]);
}
