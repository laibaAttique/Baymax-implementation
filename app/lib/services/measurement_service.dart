import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'food_log_service.dart';
import 'realtime_db.dart';

/// One body-measurement entry (Module 17, FR-8): any of the circumferences, in centimetres, taken on one day.
class BodyMeasurement {
  final DateTime date;
  final double? waistCm;
  final double? chestCm;
  final double? hipsCm;
  final double? armCm;
  final double? thighCm;
  const BodyMeasurement(this.date, {this.waistCm, this.chestCm, this.hipsCm, this.armCm, this.thighCm});

  /// The sites in the order they are shown.
  static const sites = ['Waist', 'Chest', 'Hips', 'Arm', 'Thigh'];

  double? valueOf(String site) => switch (site) {
        'Waist' => waistCm,
        'Chest' => chestCm,
        'Hips' => hipsCm,
        'Arm' => armCm,
        'Thigh' => thighCm,
        _ => null,
      };

  bool get isEmpty => sites.every((s) => valueOf(s) == null);
}

/// Checks and storage for the measurements log, at `users/{uid}/measurements/{YYYY-MM-DD}` (one entry a day; saving again replaces it).
class MeasurementService {
  MeasurementService._();
  static final MeasurementService instance = MeasurementService._();

  static const minCm = 10.0;
  static const maxCm = 300.0;

  /// Bumped after every change so open screens refresh.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// Why [text] is not a usable measurement, or null when it is empty (not measured) or fine.
  static String? problem(String text, String site) {
    final t = text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return '$site must be a number in centimetres.';
    if (v < minCm || v > maxCm) return '$site must be between ${minCm.round()} and ${maxCm.round()} cm.';
    return null;
  }

  static double? parse(String text) {
    final t = text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  /// The change in [site] between the first and the last entry that has it, or null with fewer than two such entries. [entries] are oldest first.
  static double? change(List<BodyMeasurement> entries, String site) {
    final v = [for (final e in entries) if (e.valueOf(site) != null) e.valueOf(site)!];
    return v.length < 2 ? null : v.last - v.first;
  }

  Future<List<BodyMeasurement>> range(String from, String to) {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('measurements').orderByKey().startAt(from).endAt(to).get();
      if (!snap.exists) return <BodyMeasurement>[];
      final map = RealtimeDb.plain(snap.value) as Map<String, dynamic>;
      final out = <BodyMeasurement>[];
      for (final e in map.entries) {
        final date = DateTime.tryParse(e.key);
        if (date == null || e.value is! Map) continue;
        final m = e.value as Map;
        double? n(String k) => (m[k] as num?)?.toDouble();
        out.add(BodyMeasurement(date, waistCm: n('waistCm'), chestCm: n('chestCm'), hipsCm: n('hipsCm'), armCm: n('armCm'), thighCm: n('thighCm')));
      }
      return out..sort((a, b) => a.date.compareTo(b.date));
    });
  }

  Future<void> set(BodyMeasurement m) async {
    if (m.isEmpty) throw ArgumentError('Enter at least one measurement.');
    for (final s in BodyMeasurement.sites) {
      final v = m.valueOf(s);
      if (v != null && (v < minCm || v > maxCm)) throw ArgumentError('$s must be between ${minCm.round()} and ${maxCm.round()} cm.');
    }
    await RealtimeDb.guard(() => RealtimeDb.userRef('measurements/${FoodLogService.dateKey(m.date)}').set({
          if (m.waistCm != null) 'waistCm': double.parse(m.waistCm!.toStringAsFixed(1)),
          if (m.chestCm != null) 'chestCm': double.parse(m.chestCm!.toStringAsFixed(1)),
          if (m.hipsCm != null) 'hipsCm': double.parse(m.hipsCm!.toStringAsFixed(1)),
          if (m.armCm != null) 'armCm': double.parse(m.armCm!.toStringAsFixed(1)),
          if (m.thighCm != null) 'thighCm': double.parse(m.thighCm!.toStringAsFixed(1)),
          'loggedAt': ServerValue.timestamp,
        }));
    changes.value++;
  }

  Future<void> remove(DateTime date) async {
    await RealtimeDb.guard(() => RealtimeDb.userRef('measurements/${FoodLogService.dateKey(date)}').remove());
    changes.value++;
  }
}
