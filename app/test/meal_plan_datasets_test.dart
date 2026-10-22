import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/food.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/services/allergen_dictionary.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/meal_roles.dart';
import 'package:app/services/plan_generator.dart';

HealthProfile _profile({String gender = 'Male', double height = 175, double weight = 70, int age = 30, List<String> conditions = const [], List<String> allergies = const [], String goal = 'Maintain & Stay Fit'}) {
  final dob = DateTime(DateTime.now().year - age, 1, 1).toIso8601String().substring(0, 10);
  return HealthProfile(
    fullName: 'Test User', dob: dob, gender: gender, heightValue: height, weightValue: weight, medicalConditions: conditions, foodAllergies: allergies,
    primaryGoal: goal, activityLevel: 'Moderately Active', workoutFrequency: 4,
  );
}

FoodItem _f(String name, {double grams = 200, double kcal = 200, double p = 10, double c = 25, double fat = 6, String serving = '1 bowl', String source = 'indb'}) => FoodItem(
      id: name, name: name, aliases: const [], icon: '', servingLabel: serving, grams: grams, kcal: kcal, protein: p, carbs: c, fat: fat, allergens: const [], meals: const [],
      role: 'bulk', tags: const [], source: source,
    );

void main() {
  final placeholder = AllergenDictionary.fromJsonString(File('assets/data/allergen_terms.json').readAsStringSync()).isEmpty;
  if (placeholder) {
    test('meal plan dataset tests need the real allergen dictionary (placeholder present)', () {}, skip: 'assets/data/allergen_terms.json is a placeholder: build it with ml/allergen_data/build_allergen_terms.py');
    return;
  }
  late FoodDatabase db;
  late List<FoodItem> planFoods;
  const classifier = RuleBasedClassifier();

  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    final dict = AllergenDictionary.fromJsonString(File('assets/data/allergen_terms.json').readAsStringSync());
    final all = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync(), bulkJson: File('assets/data/foods_bulk.json').readAsStringSync()).items;
    db = FoodDatabase(FoodDatabase.withDictionaryAllergens(all, dict));
    planFoods = PlanGenerator(db).planFoods;
  });

  group('which foods can be in a meal plan', () {
    MealProfile? role(FoodItem f) => MealRoles.classify(f);

    test('meals and sides are accepted with a sensible role', () {
      expect(role(_f('Rice, white, long-grain, cooked', grams: 158, kcal: 205, p: 4.2, c: 44.5, fat: 0.4, serving: '1 cup', source: 'usda'))!.role, 'carb');
      expect(role(_f('Chicken karahi', kcal: 320, p: 28, c: 8, fat: 20))!.role, 'main');
      expect(role(_f('Broccoli, cooked', grams: 156, kcal: 55, p: 3.7, c: 11, fat: 0.6, serving: '1 cup', source: 'usda'))!.role, 'veg');
      expect(role(_f('Apple, raw', grams: 182, kcal: 95, p: 0.5, c: 25, fat: 0.3, serving: '1 medium', source: 'usda'))!.role, 'fruit');
      expect(role(_f('Vegetable poha', grams: 150, kcal: 177, p: 4, c: 30, fat: 4.5))!.role, 'bfast');
      expect(role(_f('Masala chai', grams: 240, kcal: 108, p: 3, c: 14, fat: 4, serving: '1 cup'))!.role, 'drink');
      expect(role(_f('Cornflakes with milk', grams: 220, kcal: 326, p: 9, c: 60, fat: 5))!.role, 'bfast');
      expect(role(_f('Snacks, banana chips', grams: 28, kcal: 147, p: 0.7, c: 16.6, fat: 9.5, serving: '1 oz', source: 'usda'))!.role, 'snack');
    });

    test('things nobody eats as a meal are refused', () {
      expect(role(_f('Chicken, broilers or fryers, breast, raw', grams: 120, kcal: 140, p: 27, c: 0, fat: 3, source: 'usda')), isNull, reason: 'raw meat');
      expect(role(_f('Egg, whole, raw', grams: 50, kcal: 72, p: 6.3, c: 0.4, fat: 4.8, source: 'usda')), isNull, reason: 'raw egg');
      expect(role(_f('Olive oil', grams: 14, kcal: 119, p: 0, c: 0, fat: 13.5, serving: '1 tbsp', source: 'usda')), isNull, reason: 'oil');
      expect(role(_f('Soy sauce', grams: 16, kcal: 8, p: 1.3, c: 0.8, fat: 0, serving: '1 tbsp', source: 'usda')), isNull, reason: 'sauce');
      expect(role(_f('Rice, white, long-grain, raw', grams: 185, kcal: 675, p: 13, c: 148, fat: 1.2, serving: '1 cup', source: 'usda')), isNull, reason: 'dry grain');
      expect(role(_f('Foxtail Millet', grams: 100, kcal: 337, p: 11, c: 63, fat: 4, serving: 'Cup', source: 'calorica')), isNull, reason: 'dry grain by energy density');
      expect(role(_f('Beer, regular', grams: 356, kcal: 153, p: 1.6, c: 13, fat: 0, serving: '1 can', source: 'usda')), isNull, reason: 'alcohol');
      expect(role(_f('Pork chops, cooked', kcal: 300, p: 30, c: 0, fat: 20, source: 'usda')), isNull, reason: 'pork');
      expect(role(_f('Bacon, cooked', grams: 30, kcal: 160, p: 11, c: 0.5, fat: 12.5, source: 'usda')), isNull, reason: 'bacon');
      expect(role(_f('Turkey, skin, from retail parts', grams: 113, kcal: 429, p: 16, c: 0, fat: 40, source: 'usda')), isNull, reason: 'skin');
      expect(role(_f('Cola, carbonated', grams: 368, kcal: 150, p: 0, c: 39, fat: 0, serving: '1 can', source: 'usda')), isNull, reason: 'soda');
    });

    test('numbers that contradict themselves are refused', () {
      expect(role(_f('Raw banana kofta curry', grams: 350, kcal: 2195, p: 2.2, c: 11.9, fat: 237.9)), isNull, reason: 'a serving with 238 g of fat');
      expect(role(_f('Chicken curry', kcal: 150, p: 28, c: 8, fat: 20)), isNull, reason: 'energy does not match the nutrients');
      expect(role(_f('Dal', grams: 100, kcal: 200, p: 60, c: 40, fat: 5)), isNull, reason: 'more nutrients than food');
    });

    test('health tags come from the name', () {
      expect(role(_f('Apple juice', grams: 248, kcal: 114, p: 0.2, c: 28, fat: 0.3, serving: '1 cup'))!.tags, contains('highSugar'));
      expect(role(_f('Vegetable samosa', grams: 100, kcal: 250, p: 4, c: 28, fat: 13))!.tags, contains('fried'));
      expect(role(_f('Chicken nuggets', grams: 100, kcal: 250, p: 15, c: 15, fat: 15))!.tags, contains('processed'));
      expect(role(_f('Grilled chicken breast', grams: 150, kcal: 248, p: 46, c: 0, fat: 5.4))!.tags, contains('lean'));
      expect(role(_f('White bread', grams: 60, kcal: 150, p: 5, c: 28, fat: 2))!.tags, contains('refined'));
    });

    test('over the real food lists: how many are usable, in every role, from every dataset', () {
      final bySource = <String, int>{};
      final byRole = <String, int>{};
      for (final f in planFoods) {
        bySource.update(f.source, (v) => v + 1, ifAbsent: () => 1);
        byRole.update(f.role, (v) => v + 1, ifAbsent: () => 1);
      }
      // ignore: avoid_print
      print('foods in the database: ${db.items.length}; usable in plans: ${planFoods.length}; by source: $bySource; by role: $byRole');
      expect(planFoods.length, greaterThan(900));
      for (final s in ['estimate', 'usda', 'indb', 'calorica']) {
        expect(bySource[s], greaterThan(15), reason: '$s must contribute');
      }
      for (final r in ['main', 'carb', 'veg', 'fruit', 'drink', 'bfast', 'snack']) {
        expect(byRole[r], greaterThan(25), reason: '$r needs a wide choice');
      }
    });

    test('no plan food carries pork, alcohol, a raw animal food or numbers that do not add up', () {
      for (final f in planFoods.where((f) => f.fromDataset)) {
        final n = f.name.toLowerCase();
        expect(RegExp(r'\b(pork|ham|bacon|lard|beer|wine|vodka|whisk|rum\b|liquor)').hasMatch(n), isFalse, reason: f.name);
        expect(f.kcal, inInclusiveRange(15, 900), reason: f.name);
        expect((4 * f.protein + 4 * f.carbs + 9 * f.fat - f.kcal).abs(), lessThanOrEqualTo(0.3 * f.kcal + 12), reason: f.name);
        expect(f.meals, isNotEmpty, reason: f.name);
      }
    });
  });

  group('the nutrition plan is drawn from all the datasets', () {
    PersonalizedPlanLike plan(HealthProfile p, int variant) {
      final cls = classifier.classify(p);
      final n = PlanGenerator(db).generate(p, cls, variant: variant).nutrition;
      return PersonalizedPlanLike(n.meals.values.expand((l) => l).toList(), n.targetKcal);
    }

    test('across variants the plan uses USDA, the Indian Nutrient Databank, the team list and the curated catalogue', () {
      final seen = <String>{};
      var distinct = <String>{};
      for (var v = 0; v < 12; v++) {
        final items = plan(_profile(), v).items;
        seen.addAll(items.map((i) => i.food.source));
        distinct.addAll(items.map((i) => i.food.id));
      }
      // ignore: avoid_print
      print('sources used across 12 variants: $seen; distinct foods: ${distinct.length}');
      expect(seen, containsAll(['estimate', 'usda', 'indb', 'calorica']));
      expect(distinct.length, greaterThan(40));
    });

    test('each meal is close to its calorie share, for several kinds of people', () {
      for (final p in [
        _profile(),
        _profile(gender: 'Female', weight: 58, height: 160, goal: 'Lose Weight'),
        _profile(weight: 85, goal: 'Gain Muscle'),
        _profile(age: 55, conditions: ['Diabetes']),
      ]) {
        for (var v = 0; v < 6; v++) {
          final r = plan(p, v);
          final kcal = r.items.fold(0.0, (s, i) => s + i.kcal);
          expect(kcal, inInclusiveRange(r.target * 0.6, r.target * 1.45), reason: '${p.primaryGoal} variant $v: $kcal of ${r.target}');
        }
      }
    });

    test('allergies: nothing the person is allergic to, and no recipe dish whose ingredients cannot be judged', () {
      for (final allergy in ['Dairy', 'Gluten', 'Eggs', 'Nuts', 'Peanuts', 'Fish', 'Shellfish', 'Soy', 'Sesame']) {
        for (var v = 0; v < 8; v++) {
          final items = plan(_profile(allergies: [allergy]), v).items;
          for (final i in items) {
            expect(i.food.allergens, isNot(contains(allergy.toLowerCase())), reason: '${i.food.name} for $allergy');
            if (i.food.fromDataset) {
              expect(i.food.source == 'usda' || i.food.role == 'fruit' || i.food.role == 'veg', isTrue, reason: '${i.food.name} (${i.food.source}) for $allergy');
            }
          }
        }
      }
    });

    test('diabetes, heart disease and high blood pressure keep their tag filters on dataset foods too', () {
      for (var v = 0; v < 10; v++) {
        for (final i in plan(_profile(conditions: ['Diabetes']), v).items) {
          expect(i.food.tags, isNot(contains('highSugar')), reason: i.food.name);
          expect(i.food.tags, isNot(contains('refined')), reason: i.food.name);
        }
        for (final i in plan(_profile(conditions: ['Hypertension']), v).items) {
          expect(i.food.tags, isNot(contains('highSodium')), reason: i.food.name);
          expect(i.food.tags, isNot(contains('fried')), reason: i.food.name);
        }
      }
    });

    test('a person trying to lose weight gets protein-rich main dishes', () {
      final lean = <double>[];
      for (var v = 0; v < 8; v++) {
        for (final i in plan(_profile(goal: 'Lose Weight'), v).items.where((i) => i.food.role == 'main')) {
          lean.add(i.food.protein * 4 / i.food.kcal);
        }
      }
      expect(lean, isNotEmpty);
      expect(lean.reduce((a, b) => a + b) / lean.length, greaterThan(0.2));
    });

    test('the same profile and variant always give the same plan', () {
      final a = plan(_profile(), 3).items.map((i) => i.food.id).toList();
      final b = plan(_profile(), 3).items.map((i) => i.food.id).toList();
      expect(a, b);
    });

    test('with only the curated catalogue the plan still works', () {
      final curated = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
      final p = _profile();
      final n = PlanGenerator(curated).generate(p, classifier.classify(p)).nutrition;
      expect(n.meals.values.expand((l) => l), isNotEmpty);
      expect(n.meals.values.expand((l) => l).every((i) => !i.food.fromDataset), isTrue);
    });
  });
}

class PersonalizedPlanLike {
  final List<dynamic> _items;
  final int target;
  PersonalizedPlanLike(this._items, this.target);
  List<dynamic> get rawItems => _items;
  List<_Item> get items => [for (final i in _items) _Item(i.food as FoodItem, i.kcal as double)];
}

class _Item {
  final FoodItem food;
  final double kcal;
  _Item(this.food, this.kcal);
}
