import '../models/food.dart';
import '../utils/fuzzy.dart';
import 'food_database.dart';

/// Module 7, FR-3/FR-4: turns "2 rotis and a bowl of daal, 150g chicken breast"
/// into matched foods with quantities (rule-based entity extraction).
class FoodParser {
  final FoodDatabase db;
  const FoodParser(this.db);

  static const _numberWords = {
    'a': 1.0, 'an': 1.0, 'one': 1.0, 'two': 2.0, 'three': 3.0, 'four': 4.0, 'five': 5.0,
    'six': 6.0, 'seven': 7.0, 'eight': 8.0, 'nine': 9.0, 'ten': 10.0,
    'half': 0.5, 'quarter': 0.25, 'couple': 2.0,
  };

  static const _gramUnits = {'g', 'gm', 'gms', 'gram', 'grams', 'ml', 'milliliter', 'milliliters', 'millilitre', 'millilitres'};
  static const _kgUnits = {'kg', 'kgs', 'kilo', 'kilos', 'kilogram', 'kilograms', 'l', 'litre', 'litres', 'liter', 'liters'};
  static const _countUnits = {
    'cup', 'cups', 'bowl', 'bowls', 'plate', 'plates', 'piece', 'pieces', 'pcs', 'pc', 'slice', 'slices',
    'glass', 'glasses', 'serving', 'servings', 'portion', 'portions', 'spoon', 'spoons', 'tbsp', 'tsp',
    'can', 'cans', 'bar', 'bars', 'scoop', 'scoops', 'handful', 'handfuls',
  };
  static const _sizeFactors = {'small': 0.75, 'medium': 1.0, 'large': 1.3, 'big': 1.3, 'mini': 0.5};
  static const _filler = {
    'a', 'an', 'of', 'the', 'some', 'my', 'i', 'ate', 'had', 'have', 'eaten', 'eat', 'for', 'breakfast', 'lunch',
    'dinner', 'snack', 'today', 'just', 'about', 'around', 'approximately', 'with', 'also', 'then', 'in', 'morning',
  };

  List<ParsedFood> parse(String text) {
    final cleaned = text
        .toLowerCase()
        .replaceAll(RegExp(r'[\n;]'), ',')
        .replaceAll(RegExp(r'\s+(and|plus|&|\+|then|also)\s+'), ',')
        .replaceAll(RegExp(r'\b(and|plus)\b'), ',');
    final segments = cleaned.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);

    final out = <ParsedFood>[];
    for (final seg in segments) {
      final parsed = _parseSegment(seg);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  ParsedFood? _parseSegment(String segment) {
    var tokens = segment
        .replaceAllMapped(RegExp(r'(\d)([a-z])'), (m) => '${m[1]} ${m[2]}') // 150g → 150 g
        .replaceAll(RegExp(r'[^a-z0-9./\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    double? qty;
    String unit = 'serving';
    double size = 1.0;
    final nameTokens = <String>[];

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      final asNumber = _toNumber(t);
      if (qty == null && asNumber != null) {
        qty = asNumber;
        // "1 and a half" style / "2 1/2" – add a following fraction.
        if (i + 1 < tokens.length) {
          final next = _toNumber(tokens[i + 1]);
          if (next != null && next < 1) {
            qty = qty + next;
            i++;
          }
        }
        continue;
      }
      if (_gramUnits.contains(t) || _kgUnits.contains(t) || _countUnits.contains(t)) {
        if (unit == 'serving') unit = t;
        continue;
      }
      if (_sizeFactors.containsKey(t)) {
        size = _sizeFactors[t]!;
        continue;
      }
      if (_filler.contains(t)) continue;
      nameTokens.add(t);
    }

    final phrase = nameTokens.join(' ');
    if (phrase.isEmpty) return null;

    qty ??= 1;
    final item = db.match(phrase);

    double servings;
    if (item == null) {
      servings = qty;
    } else if (_gramUnits.contains(unit)) {
      servings = qty / item.grams;
    } else if (_kgUnits.contains(unit)) {
      servings = qty * 1000 / item.grams;
    } else {
      servings = qty * size;
    }
    if (unit == 'spoon' || unit == 'spoons' || unit == 'tbsp' || unit == 'tsp') {
      // Spoons are small; treat as ~1/10 of a serving unless the item is
      // already defined per spoon.
      if (item != null && !item.servingLabel.contains('tbsp') && !item.servingLabel.contains('tsp')) {
        servings = servings * 0.1;
      }
    }
    return ParsedFood(
      raw: segment,
      item: item,
      quantity: qty,
      unit: unit,
      servings: double.parse(servings.toStringAsFixed(2)),
    );
  }

  double? _toNumber(String t) {
    if (_numberWords.containsKey(t)) return _numberWords[t];
    if (t.contains('/')) {
      final parts = t.split('/');
      if (parts.length == 2) {
        final a = double.tryParse(parts[0]);
        final b = double.tryParse(parts[1]);
        if (a != null && b != null && b != 0) return a / b;
      }
      return null;
    }
    return double.tryParse(t);
  }

  /// Convenience for the chatbot: total kcal for a sentence.
  static double totalKcal(List<ParsedFood> items) => items.fold(0.0, (s, p) => s + p.kcal);

  /// Clean name for display, e.g. `2 × Roti`.
  static String describe(ParsedFood p) {
    final n = p.item?.name ?? Fuzzy.normalize(p.raw);
    return '${_fmt(p.servings)} × $n';
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
