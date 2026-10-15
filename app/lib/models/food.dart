/// A food in the local calorie database. Nutrition values are per serving
/// ([servingLabel], [grams]).
class FoodItem {
  final String id;
  final String name;
  final List<String> aliases;
  final String icon;
  final String servingLabel;
  final double grams;
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;
  final List<String> allergens;
  final List<String> meals;
  final String role;
  final List<String> tags;

  /// Where the nutrition numbers come from: `usda` (USDA FoodData Central,
  /// see [fdcId]) or `estimate` (typical-serving figure not yet verified).
  final String source;
  final String? fdcId;

  /// For foods from the team's food list: the origin the list itself names for this row (USDA, INDB, CURATED, a brand's official figures ...).
  final String? sourceNote;

  const FoodItem({
    required this.id,
    required this.name,
    required this.aliases,
    required this.icon,
    required this.servingLabel,
    required this.grams,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.allergens,
    required this.meals,
    required this.role,
    required this.tags,
    this.source = 'estimate',
    this.fdcId,
    this.sourceNote,
  });

  factory FoodItem.fromJson(Map<String, dynamic> j) {
    List<String> list(dynamic v) => (v as List? ?? const []).map((e) => e.toString()).toList();
    return FoodItem(
      id: j['id'] as String,
      name: j['name'] as String,
      aliases: list(j['aliases']),
      icon: j['icon'] as String? ?? '🍽️',
      servingLabel: j['serving'] as String? ?? '1 serving',
      grams: (j['grams'] as num).toDouble(),
      kcal: (j['kcal'] as num).toDouble(),
      protein: (j['protein'] as num).toDouble(),
      carbs: (j['carbs'] as num).toDouble(),
      fat: (j['fat'] as num).toDouble(),
      allergens: list(j['allergens']),
      meals: list(j['meals']),
      role: j['role'] as String? ?? 'main',
      tags: list(j['tags']),
      source: j['source'] as String? ?? 'estimate',
      fdcId: j['fdcId']?.toString(),
      sourceNote: j['sourceNote']?.toString(),
    );
  }

  bool get fromUsda => source == 'usda';

  /// One of the ~2,700 foods from the searchable food list (team list, Indian Nutrient Databank, USDA SR Legacy): for search and logging
  /// only, never in a generated meal plan (they have no meal slots).
  bool get isBulk => role == 'bulk' || role == 'usda';

  /// None of those sources has allergen information, so for these foods [allergens] is a guess made from the name. The app says so.
  bool get allergensEstimated => isBulk;

  /// Short provenance tag stored with logged entries, e.g. `usda:175254`, `indb:asc079`, `calorica:cal_ric001`.
  String get ref {
    switch (source) {
      case 'usda':
        return 'usda:${fdcId ?? ''}';
      case 'indb':
      case 'calorica':
        return '$source:${id.contains('_') ? id.substring(id.indexOf('_') + 1) : id}';
      default:
        return 'estimate';
    }
  }

  String get sourceLabel {
    switch (source) {
      case 'usda':
        return 'USDA FoodData Central';
      case 'indb':
        return 'Indian Nutrient Databank (values calculated from recipes)';
      case 'calorica':
        final n = (sourceNote ?? '').trim();
        if (n.isEmpty || n.toUpperCase().startsWith('CURATED')) return 'Team food list (no outside source cited)';
        return 'Team food list (original source: $n)';
      default:
        return 'Estimated typical serving';
    }
  }

  /// One or two words for list rows.
  String get sourceTag {
    switch (source) {
      case 'usda':
        return 'USDA';
      case 'indb':
        return 'INDB';
      case 'calorica':
        return 'team list';
      default:
        return 'estimate';
    }
  }

  /// Allergens in this food that match the user's allergy list.
  List<String> conflictsWith(List<String> userAllergies) {
    final mine = userAllergies.map((a) => a.toLowerCase()).toSet();
    return allergens.where(mine.contains).toList();
  }
}

/// A food the user logged, with nutrition already scaled to what they ate.
class FoodEntry {
  final String? id;
  final String date; // YYYY-MM-DD
  final String meal; // Breakfast / Lunch / Dinner / Snack
  final String name;
  final double quantity;
  final String unit;
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;
  final String source; // text | image | manual

  /// Provenance of the nutrition numbers (`usda:<fdcId>` or `estimate`).
  final String ref;

  const FoodEntry({
    this.id,
    required this.date,
    required this.meal,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.source = 'text',
    this.ref = 'estimate',
  });

  FoodEntry withId(String newId) => FoodEntry(
        id: newId,
        date: date,
        meal: meal,
        name: name,
        quantity: quantity,
        unit: unit,
        kcal: kcal,
        protein: protein,
        carbs: carbs,
        fat: fat,
        source: source,
        ref: ref,
      );

  factory FoodEntry.fromJson(Map<String, dynamic> j) => FoodEntry(
        id: (j['_id'] ?? j['id']) as String?,
        date: j['date'] as String? ?? '',
        meal: j['meal'] as String? ?? 'Snack',
        name: j['name'] as String? ?? '',
        quantity: (j['quantity'] as num?)?.toDouble() ?? 1,
        unit: j['unit'] as String? ?? 'serving',
        kcal: (j['kcal'] as num?)?.toDouble() ?? 0,
        protein: (j['protein'] as num?)?.toDouble() ?? 0,
        carbs: (j['carbs'] as num?)?.toDouble() ?? 0,
        fat: (j['fat'] as num?)?.toDouble() ?? 0,
        source: j['source'] as String? ?? 'text',
        ref: j['ref'] as String? ?? 'estimate',
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'meal': meal,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'kcal': kcal,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'source': source,
        'ref': ref,
      };
}

/// Result of parsing one food phrase out of a sentence (Module 7, FR-4).
class ParsedFood {
  final String raw;
  final FoodItem? item;
  final double quantity;
  final String unit;

  /// Number of database servings this represents.
  final double servings;

  const ParsedFood({
    required this.raw,
    required this.item,
    required this.quantity,
    required this.unit,
    required this.servings,
  });

  bool get matched => item != null;
  double get kcal => (item?.kcal ?? 0) * servings;
  double get protein => (item?.protein ?? 0) * servings;
  double get carbs => (item?.carbs ?? 0) * servings;
  double get fat => (item?.fat ?? 0) * servings;

  ParsedFood withServings(double s) =>
      ParsedFood(raw: raw, item: item, quantity: quantity, unit: unit, servings: s);

  FoodEntry toEntry({required String date, required String meal, String source = 'text'}) => FoodEntry(
        date: date,
        meal: meal,
        name: item!.name,
        quantity: double.parse(servings.toStringAsFixed(2)),
        unit: 'serving',
        kcal: double.parse(kcal.toStringAsFixed(1)),
        protein: double.parse(protein.toStringAsFixed(1)),
        carbs: double.parse(carbs.toStringAsFixed(1)),
        fat: double.parse(fat.toStringAsFixed(1)),
        source: source,
        ref: item!.ref,
      );
}
