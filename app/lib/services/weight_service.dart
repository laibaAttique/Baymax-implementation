import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'calorie_optimizer.dart';
import 'food_log_service.dart';
import 'realtime_db.dart';

/// Module 3 (FR-4): the user's weight check-ins at `users/{uid}/weights/{YYYY-MM-DD}` (one per day; saving again replaces it).
class WeightService {
  WeightService._();
  static final WeightService instance = WeightService._();

  /// Bumped after every change so open screens refresh.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static const minKg = 20.0;
  static const maxKg = 400.0;

  /// Weigh-ins between two date keys (inclusive), oldest first.
  Future<List<WeightPoint>> range(String from, String to) {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('weights').orderByKey().startAt(from).endAt(to).get();
      if (!snap.exists) return <WeightPoint>[];
      final map = RealtimeDb.plain(snap.value) as Map<String, dynamic>;
      final out = <WeightPoint>[];
      for (final e in map.entries) {
        final date = DateTime.tryParse(e.key);
        final kg = ((e.value as Map)['kg'] as num?)?.toDouble();
        if (date != null && kg != null) out.add(WeightPoint(date, kg));
      }
      return out..sort((a, b) => a.date.compareTo(b.date));
    });
  }

  Future<void> set(DateTime date, double kg) async {
    if (kg < minKg || kg > maxKg) throw ArgumentError('Weight must be between ${minKg.round()} and ${maxKg.round()} kg.');
    await RealtimeDb.guard(() => RealtimeDb.userRef('weights/${FoodLogService.dateKey(date)}').set({
          'kg': double.parse(kg.toStringAsFixed(1)),
          'loggedAt': ServerValue.timestamp,
        }));
    changes.value++;
  }

  Future<void> remove(DateTime date) async {
    await RealtimeDb.guard(() => RealtimeDb.userRef('weights/${FoodLogService.dateKey(date)}').remove());
    changes.value++;
  }
}
