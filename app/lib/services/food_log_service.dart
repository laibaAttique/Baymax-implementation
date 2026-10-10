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

  Future<void> add(List<FoodEntry> entries) async {
    if (entries.isEmpty) return;
    await RealtimeDb.guard(() async {
      final uid = RealtimeDb.uid;
      final updates = <String, Object?>{};
      for (final e in entries) {
        final key = RealtimeDb.db.ref().push().key!;
        final data = e.toJson()..remove('date'); // the date is part of the path
        updates['users/$uid/foodLog/${e.date}/$key'] = {...data, 'createdAt': ServerValue.timestamp};
      }
      await RealtimeDb.db.ref().update(updates); // one atomic multi-path write
    });
    changes.value++;
  }

  Future<void> delete(FoodEntry entry) async {
    if (entry.id == null) return;
    await RealtimeDb.guard(() => RealtimeDb.userRef('foodLog/${entry.date}/${entry.id}').remove());
    changes.value++;
  }

  static double totalKcal(List<FoodEntry> entries) => entries.fold(0.0, (s, e) => s + e.kcal);
}
