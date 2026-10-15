import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../models/food.dart';
import 'realtime_db.dart';

/// Module 7 (FE-12): the user's logged meals, stored in the Realtime Database
/// at `users/{uid}/foodLog/{YYYY-MM-DD}/{entryId}`.
class FoodLogService {
  FoodLogService._();
  static final FoodLogService instance = FoodLogService._();

  /// Bumped after every add/delete so open screens can refresh their totals.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<List<FoodEntry>> forDate(String date) {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('foodLog/$date').get();
      if (!snap.exists) return <FoodEntry>[];
      final byId = RealtimeDb.plain(snap.value) as Map<String, dynamic>;
      // Push ids are chronological, so sorting by key keeps logging order.
      final keys = byId.keys.toList()..sort();
      return [
        for (final k in keys)
          FoodEntry.fromJson({...Map<String, dynamic>.from(byId[k] as Map), 'id': k, 'date': date}),
      ];
    });
  }

  /// Total calories logged per day between two date keys (inclusive). Days without entries are absent.
  Future<Map<String, double>> kcalByDate(String from, String to) {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('foodLog').orderByKey().startAt(from).endAt(to).get();
      if (!snap.exists) return <String, double>{};
      final days = RealtimeDb.plain(snap.value) as Map<String, dynamic>;
      return {
        for (final d in days.entries)
          d.key: (d.value as Map).values.fold<double>(0, (s, e) => s + (((e as Map)['kcal'] as num?)?.toDouble() ?? 0)),
      };
    });
  }

  /// The most recent [add], kept for 30 seconds so the user can undo it (NFR-U8).
  LoggedBatch? lastLogged;

  static const undoWindow = Duration(seconds: 30);

  Future<void> add(List<FoodEntry> entries) async {
    if (entries.isEmpty) return;
    final saved = <FoodEntry>[];
    await RealtimeDb.guard(() async {
      final uid = RealtimeDb.uid;
      final updates = <String, Object?>{};
      for (final e in entries) {
        final key = RealtimeDb.db.ref().push().key!;
        final data = e.toJson()..remove('date'); // the date is part of the path
        updates['users/$uid/foodLog/${e.date}/$key'] = {...data, 'createdAt': ServerValue.timestamp};
        updates['users/$uid/foodDays/${e.date}'] = true; // marks a day with food logged (counted for XP)
        saved.add(e.withId(key));
      }
      await RealtimeDb.db.ref().update(updates); // one atomic multi-path write
    });
    lastLogged = LoggedBatch(saved, DateTime.now());
    changes.value++;
  }

  Future<void> delete(FoodEntry entry) async {
    if (entry.id == null) return;
    await RealtimeDb.guard(() async {
      await RealtimeDb.userRef('foodLog/${entry.date}/${entry.id}').remove();
      await _clearDayMarkerIfEmpty(entry.date);
    });
    changes.value++;
  }

  /// Puts back an entry that was just removed (the Undo button on the "Removed" message). The same id is reused.
  Future<void> restore(FoodEntry entry) async {
    if (entry.id == null) return;
    await RealtimeDb.guard(() async {
      final uid = RealtimeDb.uid;
      final data = entry.toJson()..remove('date');
      await RealtimeDb.db.ref().update({
        'users/$uid/foodLog/${entry.date}/${entry.id}': {...data, 'createdAt': ServerValue.timestamp},
        'users/$uid/foodDays/${entry.date}': true,
      });
    });
    changes.value++;
  }

  /// Removes what the last [add] logged, if it was less than [undoWindow] ago. Returns how many entries were removed.
  Future<int> undoLast() async {
    final batch = lastLogged;
    if (batch == null || DateTime.now().difference(batch.at) > undoWindow) return 0;
    lastLogged = null;
    await RealtimeDb.guard(() async {
      final uid = RealtimeDb.uid;
      await RealtimeDb.db.ref().update({for (final e in batch.entries) if (e.id != null) 'users/$uid/foodLog/${e.date}/${e.id}': null});
      for (final date in {for (final e in batch.entries) e.date}) {
        await _clearDayMarkerIfEmpty(date);
      }
    });
    changes.value++;
    return batch.entries.length;
  }

  Future<void> _clearDayMarkerIfEmpty(String date) async {
    final left = await RealtimeDb.userRef('foodLog/$date').get();
    if (!left.exists) await RealtimeDb.userRef('foodDays/$date').remove();
  }

  static double totalKcal(List<FoodEntry> entries) => entries.fold(0.0, (s, e) => s + e.kcal);
}

/// Entries saved by one [FoodLogService.add], with their database ids.
class LoggedBatch {
  final List<FoodEntry> entries;
  final DateTime at;
  const LoggedBatch(this.entries, this.at);

  /// Still inside the 30-second undo window?
  bool isUndoable([DateTime? now]) => (now ?? DateTime.now()).difference(at) <= FoodLogService.undoWindow;
}
