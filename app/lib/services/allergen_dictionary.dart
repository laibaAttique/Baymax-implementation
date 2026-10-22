import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import '../utils/fuzzy.dart';

/// An allergen dictionary: ingredient words and phrases, each with the allergens they carry. It is built from the Open Food Facts
/// allergens and ingredients taxonomies plus a short list written by the project team (`ml/allergen_data/build_allergen_terms.py`,
/// `assets/data/allergen_terms.json`), and is used in two places: the label scanner (Module 10) and the allergen labels of the foods
/// (so the 2,700 searchable foods no longer rely only on a name guess).
///
/// Allergen keys: gluten, dairy, nuts, peanuts, soy, shellfish, eggs, fish, sesame, celery, mustard, lupin, sulphites.
/// A peanut term carries both `peanuts` and `nuts`, so a person who ticked "Nuts" is still warned about peanuts.
class AllergenDictionary {
  /// Normalised phrase → allergens.
  final Map<String, List<String>> terms;

  /// Phrases that contain a dairy word but are not dairy (coconut milk, cocoa butter). They never cancel any other allergen.
  final Set<String> notDairy;

  final int _maxWords;

  /// Where the data comes from, for the Sources screen.
  final String source;
  final int supplementTerms;

  AllergenDictionary({required this.terms, this.notDairy = const {}, this.source = '', this.supplementTerms = 0})
      : _maxWords = [for (final k in [...terms.keys, ...notDairy]) k.split(' ').length].fold(1, (a, b) => a > b ? a : b);

  factory AllergenDictionary.fromJsonString(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    final terms = <String, List<String>>{
      for (final e in (j['terms'] as Map<String, dynamic>).entries) e.key: [for (final a in e.value as List) a.toString()],
    };
    final ex = ((j['exclusions'] as Map<String, dynamic>?)?['dairy'] as List?)?.map((e) => e.toString()).toSet() ?? <String>{};
    return AllergenDictionary(terms: terms, notDairy: ex, source: j['source']?.toString() ?? '', supplementTerms: (j['supplementTerms'] as num?)?.toInt() ?? 0);
  }

  static AllergenDictionary? _instance;
  static Future<AllergenDictionary?>? _loading;

  /// The dictionary once it has been loaded (null before, or if the asset is missing: the old word lists then still apply).
  static AllergenDictionary? get instance => _instance;

  static Future<AllergenDictionary?> ensureLoaded() {
    if (_instance != null) return Future.value(_instance);
    return _loading ??= () async {
      try {
        return _instance = AllergenDictionary.fromJsonString(await rootBundle.loadString('assets/data/allergen_terms.json'));
      } catch (_) {
        return null; // a missing or damaged file must never stop scanning: the built-in word lists still work
      } finally {
        _loading = null;
      }
    }();
  }

  @visibleForTesting
  static void useForTest(AllergenDictionary? d) => _instance = d;

  bool get isEmpty => terms.isEmpty;

  /// The allergens found in [text] and the phrase that showed each one. Longest phrase first, left to right: "soy milk" is soy (not
  /// dairy), "coconut milk" is not dairy, "peanut butter" is peanuts and nuts (not dairy).
  Map<String, String> detect(String text) {
    final tokens = Fuzzy.tokens(text).map(Fuzzy.deOcr).toList();
    final found = <String, String>{};
    if (tokens.isEmpty) return found;

    // Spans where a dairy word is not dairy.
    final plant = <(int, int)>[];
    for (var i = 0; i < tokens.length; i++) {
      for (var len = _maxWords; len >= 2; len--) {
        if (i + len > tokens.length) continue;
        if (_lookup(notDairy, tokens, i, len)) {
          plant.add((i, i + len));
          break;
        }
      }
    }

    var i = 0;
    while (i < tokens.length) {
      var matched = 0;
      for (var len = _maxWords; len >= 1 && matched == 0; len--) {
        if (i + len > tokens.length) continue;
        final phrase = _phrase(tokens, i, len);
        final allergens = terms[phrase] ?? terms[_singularLast(tokens, i, len)];
        if (allergens == null) continue;
        matched = len;
        final insidePlant = plant.any((s) => i >= s.$1 && i + len <= s.$2);
        for (final a in allergens) {
          if (a == 'dairy' && insidePlant) continue;
          found.putIfAbsent(a, () => phrase);
        }
      }
      i += matched == 0 ? 1 : matched;
    }
    return found;
  }

  static String _phrase(List<String> t, int i, int len) => t.sublist(i, i + len).join(' ');

  static String _singularLast(List<String> t, int i, int len) => [...t.sublist(i, i + len - 1), Fuzzy.singular(t[i + len - 1])].join(' ');

  static bool _lookup(Set<String> set, List<String> t, int i, int len) => set.contains(_phrase(t, i, len)) || set.contains(_singularLast(t, i, len));
}
