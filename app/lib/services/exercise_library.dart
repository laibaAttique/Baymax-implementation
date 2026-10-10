import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/plan.dart';
import 'catalog_service.dart';

/// The exercise catalogue used by the plan generator (Module 3, FR-2).
///
/// The data lives in Cloud Firestore (`exercises` collection, seeded from
/// `assets/data/exercises.json`) so it can be corrected or extended without
/// releasing a new app version. The bundled JSON is the offline fallback.
/// Each exercise records where its energy value (2024 Compendium of Physical
/// Activities code), muscles and technique text come from.
class ExerciseLibrary {
  ExerciseLibrary._();

  static const _warmUpId = 'warmup';
  static const _coolDownId = 'cooldown';
  static const _minimumSize = 10;

  static List<Exercise> _items = const [];
  static Future<void>? _loading;

  static CatalogOrigin origin = CatalogOrigin.bundled;
  static int? version;

  static bool get isLoaded => _items.isNotEmpty;

  /// Loads the catalogue once: Firestore first (cached on the device), then the
  /// copy bundled with the app.
  static Future<void> load() {
    if (isLoaded) return Future.value();
    return _loading ??= _loadFresh().whenComplete(() => _loading = null);
  }

  static Future<void> _loadFresh() async {
    final remote = await CatalogService.fetch<Exercise>(
      collection: 'exercises',
      metaId: 'exercises',
      fromDoc: (id, data) => Exercise.fromJson({...data, 'id': id}),
    );
    if (remote != null && _isUsable(remote.items)) {
      _items = remote.items;
      origin = remote.origin;
      version = remote.version;
      return;
    }
    loadFromJsonString(await rootBundle.loadString('assets/data/exercises.json'));
  }

  /// Used for the bundled fallback and by tests.
  static void loadFromJsonString(String source) {
    final list = jsonDecode(source) as List;
    _items = [for (final e in list) Exercise.fromJson(e as Map<String, dynamic>)];
    origin = CatalogOrigin.bundled;
    version = null;
  }

  /// A catalogue is only used if it contains what the generator relies on.
  static bool _isUsable(List<Exercise> items) {
    final ids = items.map((e) => e.id).toSet();
    return items.length >= _minimumSize && ids.contains(_warmUpId) && ids.contains(_coolDownId);
  }

  static List<Exercise> get _checked {
    if (_items.isEmpty) throw StateError('ExerciseLibrary.load() must complete before use.');
    return _items;
  }

  /// All training exercises (warm-up and cool-down excluded).
  static List<Exercise> get all =>
      [for (final e in _checked) if (e.id != _warmUpId && e.id != _coolDownId) e];

  static Exercise get warmUp => byId(_warmUpId)!;
  static Exercise get coolDown => byId(_coolDownId)!;

  static Exercise? byId(String id) {
    for (final e in _checked) {
      if (e.id == id) return e;
    }
    return null;
  }

  static String get originLabel {
    final n = _items.length;
    switch (origin) {
      case CatalogOrigin.server:
        return 'Exercise library: $n exercises, synced from Firestore';
      case CatalogOrigin.cache:
        return 'Exercise library: $n exercises (Firestore, saved on this device)';
      case CatalogOrigin.bundled:
        return 'Exercise library: $n exercises (offline copy bundled with the app)';
    }
  }
}
