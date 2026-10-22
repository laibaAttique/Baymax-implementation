import '../utils/fuzzy.dart';
import 'allergen_dictionary.dart';

class AllergenHit {
  /// The allergy from the user's profile (e.g. "Dairy").
  final String allergen;

  /// The ingredient word/phrase that triggered it (e.g. "milk powder").
  final String matchedTerm;

  /// False when the match tolerated OCR/spelling errors ("possible match").
  final bool exact;

  const AllergenHit(this.allergen, this.matchedTerm, {required this.exact});
}

class IngredientCheck {
  final String text;
  final List<AllergenHit> hits;
  const IngredientCheck(this.text, this.hits);
  bool get flagged => hits.isNotEmpty;
}

class ScanResult {
  final String rawText;
  final List<IngredientCheck> ingredients;

  /// Allergens found in the "may contain / traces" statement.
  final List<AllergenHit> traceHits;
  final List<String> userAllergies;

  const ScanResult({
    required this.rawText,
    required this.ingredients,
    required this.traceHits,
    required this.userAllergies,
  });

  /// Distinct allergens found directly in the ingredient list.
  Set<String> get allergensFound => {
        for (final i in ingredients)
          for (final h in i.hits) h.allergen,
      };

  Set<String> get traceAllergens => {for (final h in traceHits) h.allergen};

  bool get hasDirectHit => allergensFound.isNotEmpty;
  bool get hasTraceHit => traceAllergens.isNotEmpty;
  bool get isSafe => !hasDirectHit && !hasTraceHit;
}

/// Module 8, FR-3/FR-4: compares scanned ingredient text with the user's
/// allergy list using synonym dictionaries and fuzzy matching.
class AllergenMatcher {
  AllergenMatcher._();

  /// Allergen → words/phrases that indicate it.
  static const synonyms = <String, List<String>>{
    'gluten': [
      'wheat', 'barley', 'rye', 'malt', 'semolina', 'spelt', 'durum', 'farina', 'couscous', 'bulgur',
      'seitan', 'triticale', 'gluten', 'maida', 'atta', 'suji', 'sooji', 'flour', 'oats', 'oat',
    ],
    'dairy': [
      'milk', 'cream', 'butter', 'cheese', 'yogurt', 'yoghurt', 'whey', 'casein', 'caseinate', 'lactose',
      'ghee', 'paneer', 'curd', 'custard', 'buttermilk', 'milk powder', 'skimmed milk', 'dahi', 'khoya',
    ],
    'nuts': [
      'peanut', 'almond', 'cashew', 'walnut', 'pistachio', 'hazelnut', 'pecan', 'macadamia', 'brazil nut',
      'pine nut', 'groundnut', 'marzipan', 'praline', 'nut', 'badam', 'pista', 'kaju',
    ],
    'soy': [
      'soy', 'soya', 'soybean', 'soybeans', 'soy lecithin', 'tofu', 'edamame', 'miso', 'tempeh',
      'textured vegetable protein',
    ],
    'shellfish': [
      'shrimp', 'prawn', 'crab', 'lobster', 'crayfish', 'crawfish', 'clam', 'mussel', 'oyster', 'scallop',
      'shellfish', 'krill', 'langoustine',
    ],
    'eggs': [
      'egg', 'egg white', 'egg yolk', 'albumin', 'albumen', 'ovalbumin', 'lysozyme', 'mayonnaise',
      'meringue', 'ovomucoid', 'eggnog',
    ],
    'fish': ['fish', 'salmon', 'tuna', 'cod', 'anchovy', 'anchovies', 'sardine', 'mackerel', 'fish sauce'],
    'sesame': ['sesame', 'tahini', 'til'],
    'peanuts': ['peanut', 'groundnut', 'groundnuts', 'arachis', 'monkey nut', 'moongphali', 'mungfali'],
  };

  /// Phrases that contain an allergen word but are NOT that allergen.
  static const _exclusions = <String, List<String>>{
    'dairy': [
      'coconut milk', 'almond milk', 'soy milk', 'soya milk', 'oat milk', 'rice milk', 'cashew milk',
      'cocoa butter', 'shea butter', 'peanut butter', 'almond butter', 'coconut cream', 'cream of tartar',
      'nut butter', 'butter bean', 'butternut',
    ],
    'gluten': [
      'rice flour', 'corn flour', 'maize flour', 'gram flour', 'chickpea flour', 'potato flour',
      'tapioca flour', 'almond flour', 'coconut flour', 'soy flour', 'besan', 'gluten free', 'gluten-free',
      'cornflour', 'buckwheat flour', 'millet flour',
    ],
    'nuts': ['nutmeg', 'coconut', 'butternut', 'doughnut', 'donut', 'chestnut water'],
    'eggs': ['eggplant', 'egg plant', 'egg free', 'eggless'],
    'soy': ['soy free'],
  };

  static final _traceMarker = RegExp(
    r'(may contain|might contain|traces? of|manufactured (in|on)|produced (in|on)|processed (in|on)|made (in|on) (a )?(shared )?(facility|line|equipment))',
    caseSensitive: false,
  );

  static String _key(String allergy) => allergy.trim().toLowerCase();

  static List<String> synonymsFor(String allergy) {
    final k = _key(allergy);
    return synonyms[k] ?? [k];
  }

  /// Analyse OCR/pasted [text] against the user's [allergies].
  static ScanResult analyze(String text, List<String> allergies) {
    final userAllergies = allergies.where((a) => a.trim().isNotEmpty && a != 'None' && a != 'Other').toList();

    var body = text.replaceAll(RegExp(r'[\r\n]+'), ' ');
    String trace = '';
    final tm = _traceMarker.firstMatch(body);
    if (tm != null) {
      trace = body.substring(tm.start);
      body = body.substring(0, tm.start);
    }

    // Drop anything before an "Ingredients:" heading (nutrition tables, brand text).
    final heading = RegExp(r'ingredients?\s*[:\-]', caseSensitive: false).firstMatch(body);
    if (heading != null) body = body.substring(heading.end);

    final phrases = body
        .replaceAll(RegExp(r'[()\[\]{}]'), ',')
        .split(RegExp(r'[,;•·|]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final checks = <IngredientCheck>[
      for (final p in phrases) IngredientCheck(p, _hitsIn(p, userAllergies)),
    ];

    final traceHits = trace.isEmpty ? <AllergenHit>[] : _hitsIn(trace, userAllergies);

    return ScanResult(
      rawText: text,
      ingredients: checks,
      traceHits: traceHits,
      userAllergies: userAllergies,
    );
  }

  static List<AllergenHit> _hitsIn(String phrase, List<String> allergies) {
    final hits = <AllergenHit>[];
    // The Open Food Facts based dictionary (about 1,800 ingredient names) is asked first; the built-in word lists and the fuzzy
    // matching below then catch whatever it does not know, so a warning is never lost by adding the dictionary.
    final dict = AllergenDictionary.instance?.detect(phrase) ?? const <String, String>{};
    for (final allergy in allergies) {
      final fromDictionary = dict[_key(allergy)];
      if (fromDictionary != null) {
        hits.add(AllergenHit(allergy, fromDictionary, exact: true));
        continue;
      }
      final hit = _matchOne(phrase, allergy);
      if (hit != null) hits.add(hit);
    }
    return hits;
  }

  static AllergenHit? _matchOne(String phrase, String allergy) {
    // Space-padded so whole-word checks are simple `contains` calls.
    var hay = ' ${Fuzzy.tokens(phrase).map(Fuzzy.deOcr).join(' ')} ';

    for (final ex in _exclusions[_key(allergy)] ?? const <String>[]) {
      hay = hay.replaceAll(' ${Fuzzy.normalize(ex)} ', ' ');
    }

    final terms = synonymsFor(allergy);

    // 1. Exact whole-word / whole-phrase match (optional plural).
    for (final term in terms) {
      final t = Fuzzy.normalize(term);
      if (hay.contains(' $t ') || hay.contains(' ${t}s ') || hay.contains(' ${t}es ')) {
        return AllergenHit(allergy, term, exact: true);
      }
    }

    // 2. Fuzzy: single-word terms against each token (OCR / spelling errors).
    final tokens = hay.trim().split(' ').where((t) => t.length >= 4).toList();
    for (final term in terms) {
      final t = Fuzzy.normalize(term);
      if (t.contains(' ')) continue;
      for (final token in tokens) {
        if (Fuzzy.wordsMatch(t, token) || Fuzzy.wordsMatch(t, Fuzzy.singular(token))) {
          return AllergenHit(allergy, term, exact: false);
        }
      }
    }
    return null;
  }
}
