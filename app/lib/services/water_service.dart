import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'food_log_service.dart';
import 'realtime_db.dart';

/// Module 8 (FR-5): daily water intake, kept apart from the calorie log. Stored at `users/{uid}/water/{YYYY-MM-DD}/ml`.
class WaterService {
  WaterService._();
  static final WaterService instance = WaterService._();

  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static const maxMl = 20000;
  static const glassMl = 250;

  Future<int> forDate(DateTime d) {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('water/${FoodLogService.dateKey(d)}/ml').get();
      return snap.exists ? ((snap.value as num?)?.toInt() ?? 0) : 0;
    });
  }

  /// Sets the day's total (clamped to 0..[maxMl]) and returns the stored value.
  Future<int> set(DateTime d, int ml) async {
    final v = ml.clamp(0, maxMl);
    await RealtimeDb.guard(() => RealtimeDb.userRef('water/${FoodLogService.dateKey(d)}').set({'ml': v, 'updatedAt': ServerValue.timestamp}));
    changes.value++;
    return v;
  }
}
