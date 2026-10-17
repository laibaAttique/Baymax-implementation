import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/plan.dart';

/// Module 4 knowledge base, part 1: the free-exercise-db catalogue (871 exercises) with Compendium MET mappings.
///
/// Built offline by `ml/exercise_catalog/build_catalog.py` into `assets/data/exercise_catalog.json` (pinned dataset commit,
/// idempotent). It is bundled with the app, so it is read once from the device and never downloaded during normal use.
/// Exercise photos are loaded on demand from the dataset's repository at the same pinned commit.
///
/// Entries that the curated library (`ExerciseLibrary`) already covers are kept here for photos and traceability but
/// are not offered separately, so an exercise never appears twice.
class ExerciseCatalog {
  ExerciseCatalog._();

  static const asset = 'assets/data/exercise_catalog.json';

  /// Dataset categories the plan generator may schedule. Lifting sports are excluded by the program rule PRG-NO-MAXIMAL.
  static const plannableCategories = {'strength', 'cardio', 'plyometrics', 'stretching'};

  static List<Exercise> _all = const [];
  static Map<String, Exercise> _byId = const {};
  static Map<String, List<String>> _curatedLinks = const {};
  static Map<String, dynamic> meta = const {};
  static Future<void>? _loading;

  static bool get isLoaded => _all.isNotEmpty;

  static Future<void> load() {
    if (isLoaded) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  static Future<void> _load() async {
    final text = await rootBundle.loadString(asset);
    // About 2 MB of JSON: decode off the UI thread.
    final parsed = await compute(_parse, text);
    _apply(parsed);
  }

  /// Synchronous load, used by tests.
  static void loadFromJsonString(String text) => _apply(_parse(text));

  static void _apply(_Parsed p) {
    _all = p.exercises;
    _byId = {for (final e in p.exercises) e.id: e};
    _curatedLinks = p.curatedLinks;
    meta = p.meta;
  }

  static void clear() {
    _all = const [];
    _byId = const {};
    _curatedLinks = const {};
    meta = const {};
  }

  /// Every imported catalogue exercise, including those the curated library covers.
  static List<Exercise> get all => _all;

  static Exercise? byId(String datasetId) => _byId[datasetId];

  /// Curated library ids that are based on this dataset entry.
  static List<String> curatedIdsFor(String datasetId) => _curatedLinks[datasetId] ?? const [];

  /// Catalogue exercises not already in the curated library.
  static Iterable<Exercise> get uncurated => _all.where((e) => !_curatedLinks.containsKey(e.id));

  /// Photos for an exercise: its own, or — for a curated exercise that is an exact match to a dataset entry — that
  /// entry's photos. A "related" match shows no photos, because the dataset variant may look different.
  static List<String> imagesFor(Exercise e) {
    if (e.imageUrls.isNotEmpty) return e.imageUrls;
    final ref = e.referenceId;
    if (ref == null || e.referenceMatch != 'exact') return const [];
    return _byId[ref]?.imageUrls ?? const [];
  }

  /// Filtered view of the catalogue (all filters optional).
  static List<Exercise> query({
    Set<String>? equipment,
    String? group,
    String? category,
    String? muscle,
    int? maxLevel,
    bool onlyWithMet = false,
    bool includeCurated = false,
  }) {
    final m = muscle?.toLowerCase();
    return [
      for (final e in includeCurated ? _all : uncurated)
        if ((equipment == null || equipment.contains(e.equipmentKey)) &&
            (group == null || e.group == group) &&
            (category == null || e.category == category) &&
            (m == null || e.muscles.any((x) => x.toLowerCase() == m)) &&
            (maxLevel == null || e.level <= maxLevel) &&
            (!onlyWithMet || e.hasMet))
          e,
    ];
  }

  /// Exercises the plan generator may add for someone who owns [owned] equipment: equipment-based only (body-weight
  /// entries were reviewed by the team and the suitable ones are already in the curated library), a Compendium MET
  /// mapping, and a category this app programs. Safety rules are applied afterwards by the generator.
  static List<Exercise> plannableWith(Set<String> owned) {
    if (owned.isEmpty || !isLoaded) return const [];
    return [
      for (final e in uncurated)
        if (owned.contains(e.equipmentKey) &&
            e.equipmentKey != 'none' &&
            e.equipmentKey != 'other' &&
            e.hasMet &&
            plannableCategories.contains(e.category))
          e,
    ];
  }

  /// exact / approximate / unmatched counts, from the build.
  static Map<String, int> get metCounts => {
        for (final entry in ((meta['metMatches'] as Map?) ?? const {}).entries) entry.key.toString(): (entry.value as num).toInt(),
      };

  static String get datasetCommit => meta['commit'] as String? ?? '';
}

class _Parsed {
  final List<Exercise> exercises;
  final Map<String, List<String>> curatedLinks;
  final Map<String, dynamic> meta;
  const _Parsed(this.exercises, this.curatedLinks, this.meta);
}

_Parsed _parse(String text) {
  final json = jsonDecode(text) as Map<String, dynamic>;
  final list = json['exercises'] as List;
  final exercises = <Exercise>[];
  final links = <String, List<String>>{};
  for (final raw in list) {
    final j = raw as Map<String, dynamic>;
    exercises.add(Exercise.fromCatalog(j));
    final curated = (j['curatedAs'] as List? ?? const []);
    if (curated.isNotEmpty) links[j['id'] as String] = [for (final c in curated) (c as Map)['id'] as String];
  }
  final meta = Map<String, dynamic>.from(json['meta'] as Map)..remove('warnings');
  return _Parsed(exercises, links, meta);
}
