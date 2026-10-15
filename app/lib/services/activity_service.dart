import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'food_log_service.dart';
import 'realtime_db.dart';

/// One completed workout, stored at `users/{uid}/activity/{YYYY-MM-DD}`.
class ActivityEntry {
  final String date;
  final int minutes;
  final int kcal;
  const ActivityEntry(this.date, this.minutes, this.kcal);
}

/// Modules 11 and 14: which days the user completed their workout. This is the activity log the fitness score,
/// badges, streaks and inactivity detection read.
class ActivityService {
  ActivityService._();
  static final ActivityService instance = ActivityService._();

  /// Bumped after every change so open screens refresh.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// Entries between two date keys (inclusive), keyed by date.
  Future<Map<String, ActivityEntry>> range(String from, String to) {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('activity').orderByKey().startAt(from).endAt(to).get();
      if (!snap.exists) return <String, ActivityEntry>{};
      final map = RealtimeDb.plain(snap.value) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          e.key: ActivityEntry(e.key, ((e.value as Map)['minutes'] as num?)?.toInt() ?? 0, ((e.value as Map)['kcal'] as num?)?.toInt() ?? 0),
      };
    });
  }

  /// Date of the most recent completed workout, or null if there never was one.
  Future<DateTime?> lastWorkoutDate() {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('activity').orderByKey().limitToLast(1).get();
      if (!snap.exists) return null;
      final key = (RealtimeDb.plain(snap.value) as Map<String, dynamic>).keys.first;
      return DateTime.tryParse(key);
    });
  }

  Future<void> markDone(DateTime date, {required int minutes, required int kcal}) async {
    await RealtimeDb.guard(() => RealtimeDb.userRef('activity/${FoodLogService.dateKey(date)}').set({
          'workoutDone': true,
          'minutes': minutes.clamp(0, 600),
          'kcal': kcal.clamp(0, 5000),
          'completedAt': ServerValue.timestamp,
        }));
    changes.value++;
  }

  Future<void> undo(DateTime date) async {
    await RealtimeDb.guard(() => RealtimeDb.userRef('activity/${FoodLogService.dateKey(date)}').remove());
    changes.value++;
  }

  Future<bool> isDone(DateTime date) {
    return RealtimeDb.guard(() async => (await RealtimeDb.userRef('activity/${FoodLogService.dateKey(date)}').get()).exists);
  }
}
