import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/food.dart';
import 'catalog_service.dart';
import '../utils/fuzzy.dart';

/// In-memory calorie database (Module 7, FE-5 / FE-10). The data is fetched
/// from Cloud Firestore (see [CatalogService]); `assets/data/foods.json`
/// is only the offline fallback and the source the Firestore catalogue is
/// seeded from.
class FoodDatabase {
  final List<FoodItem> items;

  /// Where this copy of the catalogue came from (Firestore, device cache, or
  /// the file bundled with the app) and its version.
  final CatalogOrigin origin;
  final int? version;
  final Map<String, FoodItem> _byId;

  /// Normalised name/alias → item, for exact lookups.
  final Map<String, FoodItem> _byKey = {};

  FoodDatabase(this.items, {this.origin = CatalogOrigin.bundled, this.version}) : _byId = {for (final i in items) i.id: i} {
    for (final item in items) {
      for (final key in [item.name, ...item.aliases]) {
        _byKey.putIfAbsent(Fuzzy.normalize(key), () => item);
      }
    }
  }

  factory FoodDatabase.fromJsonString(String source) {
    final list = jsonDecode(source) as List;
    return FoodDatabase(list.map((e) => FoodItem.fromJson(e as Map<String, dynamic>)).toList());
  }

  static FoodDatabase? _instance;
  static Future<FoodDatabase>? _loading;

  /// Loads the catalogue once: Cloud Firestore first (cached on the device),
  /// falling back to the copy bundled with the app when offline on first run.
  static Future<FoodDatabase> load() {
    if (_instance != null) return Future.value(_instance);
    return _loading ??= _loadFresh().whenComplete(() => _loading = null);
  }

  static Future<FoodDatabase> _loadFresh() async {
    final remote = await CatalogService.fetch<FoodItem>(
      collection: 'foods',
      metaId: 'foods',
      fromDoc: (id, data) => FoodItem.fromJson({...data, 'id': id}),
    );
    if (remote != null && remote.items.isNotEmpty) {
      return _instance = FoodDatabase(remote.items, origin: remote.origin, version: remote.version);
    }
    return _instance = FoodDatabase.fromJsonString(await rootBundle.loadString('assets/data/foods.json'));
  }

  /// One-line description of the data in use, shown under food search.
  String get originLabel {
    final n = items.length;
    switch (origin) {
      case CatalogOrigin.server:
        return 'Food catalogue: $n foods, synced from Firestore';
      case CatalogOrigin.cache:
        return 'Food catalogue: $n foods (Firestore, saved on this device)';
      case CatalogOrigin.bundled:
        return 'Food catalogue: $n foods (offline copy bundled with the app)';
    }
  }

  static FoodDatabase? get loaded => _instance;

  FoodItem? byId(String id) => _byId[id];

  /// Best match for a short food phrase, or null if nothing is close enough.
  FoodItem? match(String phrase) {
    final key = Fuzzy.normalize(phrase);
    if (key.isEmpty) return null;

    final exact = _byKey[key] ?? _byKey[_singularPhrase(key)];
    if (exact != null) return exact;

    final results = search(phrase, limit: 1, minScore: 0.62);
    return results.isEmpty ? null : results.first;
  }

  String _singularPhrase(String phrase) => phrase.split(' ').map(Fuzzy.singular).join(' ');

  /// Ranked search for the "search foods" UI and for [match].
  List<FoodItem> search(String query, {int limit = 8, double minScore = 0.45}) {
    final q = Fuzzy.normalize(query);
    if (q.isEmpty) return const [];
    final qSing = _singularPhrase(q);
    final qTokens = qSing.split(' ');

    final scored = <MapEntry<FoodItem, double>>[];
    for (final item in items) {
      var best = 0.0;
      for (final key in [item.name, ...item.aliases]) {
        final k = Fuzzy.normalize(key);
        final kSing = _singularPhrase(k);
        double s;
        if (k == q || kSing == qSing) {
          s = 1.0;
        } else if (kSing.startsWith(qSing) || k.startsWith(q)) {
          s = 0.9;
        } else if (kSing.contains(qSing)) {
          s = 0.8;
        } else {
          // Every query token appears (or fuzzily appears) in the key.
          final kTokens = kSing.split(' ');
          var hits = 0;
          for (final t in qTokens) {
            if (kTokens.any((kt) => kt == t || (t.length >= 4 && Fuzzy.wordsMatch(kt, t)))) hits++;
          }
          s = hits == 0 ? 0 : 0.5 + 0.3 * (hits / qTokens.length) - (kTokens.length > qTokens.length ? 0.05 : 0);
          if (hits < qTokens.length) s *= 0.8;
        }
        if (s > best) best = s;
      }
      if (best >= minScore) scored.add(MapEntry(item, best));
    }
    scored.sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.name.length.compareTo(b.key.name.length);
    });
    return scored.take(limit).map((e) => e.key).toList();
  }
}
