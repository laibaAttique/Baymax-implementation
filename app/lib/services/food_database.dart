import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
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

  /// The normalised name and aliases of every item (and their singular forms), computed once: with ~2,800 foods the search runs on
  /// every keystroke and must not normalise the same text again each time.
  final List<List<(String, String)>> _keys = [];

  FoodDatabase(this.items, {this.origin = CatalogOrigin.bundled, this.version}) : _byId = {for (final i in items) i.id: i} {
    for (final item in items) {
      final keys = <(String, String)>[];
      for (final key in [item.name, ...item.aliases]) {
        final k = Fuzzy.normalize(key);
        _byKey.putIfAbsent(k, () => item);
        keys.add((k, _singularPhrase(k)));
      }
      _keys.add(keys);
    }
  }

  factory FoodDatabase.fromJsonString(String source, {String? bulkJson}) {
    final list = jsonDecode(source) as List;
    final base = list.map((e) => FoodItem.fromJson(e as Map<String, dynamic>)).toList();
    return FoodDatabase(withBulk(base, bulkJson));
  }

  /// The curated catalogue followed by the searchable food list (Module 8, mockup M23.1: a search over 1,000+ foods): the team's food
  /// list, the Indian Nutrient Databank and USDA SR Legacy. A food from the list is left out when the curated catalogue already has a
  /// food of the same name, so the curated one (with its meal roles and checked values) always wins.
  static List<FoodItem> withBulk(List<FoodItem> base, String? bulkJson) {
    if (bulkJson == null || bulkJson.isEmpty) return base;
    try {
      final taken = {for (final b in base) ...[b.name, ...b.aliases].map(Fuzzy.normalize)};
      final ids = {for (final b in base) b.id};
      final bulk = <FoodItem>[];
      for (final e in jsonDecode(bulkJson) as List) {
        final item = FoodItem.fromJson(e as Map<String, dynamic>);
        if (ids.contains(item.id) || taken.contains(Fuzzy.normalize(item.name))) continue;
        bulk.add(item);
      }
      return [...base, ...bulk];
    } catch (_) {
      return base; // a damaged bulk file must never take the curated catalogue down with it
    }
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
      // The food list lives in Firestore (seeded with tools/seed_firestore.js). The bundled copy is only used when Firestore does not
      // have it yet (an older catalogue holding just the curated foods), so a failed or partial seed never loses the search.
      final hasList = remote.items.where((i) => i.isBulk).length >= 500;
      final items = hasList ? remote.items : withBulk(remote.items, await _bulkAsset());
      return _instance = FoodDatabase(items, origin: remote.origin, version: remote.version);
    }
    return _instance = FoodDatabase.fromJsonString(await rootBundle.loadString('assets/data/foods.json'), bulkJson: await _bulkAsset());
  }

  static Future<String?> _bulkAsset() async {
    try {
      return await rootBundle.loadString('assets/data/foods_bulk.json');
    } catch (_) {
      return null;
    }
  }

  /// One-line description of the data in use, shown under food search.
  String get originLabel {
    final bulk = items.where((i) => i.isBulk).length;
    final n = items.length - bulk;
    if (bulk > 0) {
      final where = origin == CatalogOrigin.server
          ? 'synced from Firestore'
          : origin == CatalogOrigin.cache
              ? 'saved on this device'
              : 'offline copy bundled with the app';
      return 'Food database: ${items.length} foods, $where. Allergens of the $bulk searchable foods are estimated from the name.';
    }
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

  /// Lets a test use a catalogue built from the bundled files instead of Firestore.
  @visibleForTesting
  static void useForTest(FoodDatabase? db) => _instance = db;

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
    for (var idx = 0; idx < items.length; idx++) {
      final item = items[idx];
      var best = 0.0;
      for (final (k, kSing) in _keys[idx]) {
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
      if (c != 0) return c;
      if (a.key.isBulk != b.key.isBulk) return a.key.isBulk ? 1 : -1; // curated foods first
      return a.key.name.length.compareTo(b.key.name.length);
    });
    return scored.take(limit).map((e) => e.key).toList();
  }
}
