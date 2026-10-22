import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/food.dart';
import 'package:app/services/allergen_dictionary.dart';
import 'package:app/services/allergen_matcher.dart';
import 'package:app/services/food_database.dart';

void main() {
  late AllergenDictionary dict;

  // The public repository carries an empty placeholder (the licence of the Open Food Facts taxonomy files is not confirmed); these tests
  // need the real file built by ml/allergen_data/build_allergen_terms.py.
  final placeholder = AllergenDictionary.fromJsonString(File('assets/data/allergen_terms.json').readAsStringSync()).isEmpty;
  if (placeholder) {
    test('allergen dictionary tests need the real dictionary file (placeholder present)', () {}, skip: 'assets/data/allergen_terms.json is a placeholder: build it with ml/allergen_data/build_allergen_terms.py');
    return;
  }

  setUpAll(() => dict = AllergenDictionary.fromJsonString(File('assets/data/allergen_terms.json').readAsStringSync()));
  tearDown(() => AllergenDictionary.useForTest(null));

  Set<String> found(String text) => dict.detect(text).keys.toSet();

  group('the dictionary built from the Open Food Facts taxonomies', () {
    test('knows the ingredient names of every allergen the profile offers', () {
      expect(found('cheddar cheese'), {'dairy'});
      expect(found('whey powder'), {'dairy'});
      expect(found('wheat flour'), {'gluten'});
      expect(found('semolina'), {'gluten'});
      expect(found('prawns'), {'shellfish'});
      expect(found('oysters'), {'shellfish'});
      expect(found('anchovy paste'), {'fish'});
      expect(found('egg white'), {'eggs'});
      expect(found('tahini'), {'sesame'});
      expect(found('soy sauce'), {'soy'});
      expect(found('cashew'), {'nuts'});
      expect(found('groundnut oil'), containsAll(['peanuts', 'nuts'])); // a nut-allergic person is warned about peanuts too
    });

    test('the longest phrase wins: plant milks and butters are not dairy', () {
      expect(found('coconut milk'), isEmpty);
      expect(found('oat milk'), isEmpty);
      expect(found('cocoa butter'), isEmpty);
      expect(found('almond milk'), {'nuts'}); // not dairy, but still a nut
      expect(found('soy milk'), {'soy'});
      expect(found('peanut butter'), {'peanuts', 'nuts'});
      expect(found('milk chocolate'), contains('dairy'));
      expect(found('coconut milk, cheese'), {'dairy'}); // the plant milk does not hide the cheese next to it
    });

    test('words that only look like allergens are left alone', () {
      for (final t in ['eggplant', 'butternut squash', 'rice flour', 'nutmeg', 'coconut', 'cream of tartar', 'apple', 'broccoli']) {
        expect(found(t), isEmpty, reason: t);
      }
    });

    test('regional words the team added', () {
      expect(found('mayonnaise'), {'eggs'});
      expect(found('dahi'), {'dairy'});
      expect(found('naan'), {'gluten'});
      expect(found('chicken paneer tikka'), {'dairy'});
      expect(found('moongphali'), containsAll(['peanuts', 'nuts']));
    });

    test('plural forms, capitals and scanning slips', () {
      expect(found('Almonds, Cashews'), {'nuts'});
      expect(found('MILK'), {'dairy'});
      expect(found('mi1k powder'), {'dairy'}); // "1" read for "l"
      expect(found(''), isEmpty);
    });

    test('names the source and how many terms the team added', () {
      expect(dict.source, contains('Open Food Facts'));
      expect(dict.supplementTerms, greaterThan(50));
      expect(dict.terms.length, greaterThan(1500));
    });
  });

  group('the label scanner uses it', () {
    test('finds allergens the built-in lists do not know', () {
      AllergenDictionary.useForTest(null);
      final without = AllergenMatcher.analyze('Ingredients: water, mascarpone, sugar', ['Dairy']);
      AllergenDictionary.useForTest(dict);
      final withDict = AllergenMatcher.analyze('Ingredients: water, mascarpone, sugar', ['Dairy']);
      expect(without.allergensFound, isEmpty);
      expect(withDict.allergensFound, {'Dairy'});
    });

    test('a new profile choice (Peanuts) works on its own', () {
      AllergenDictionary.useForTest(dict);
      final r = AllergenMatcher.analyze('Ingredients: sugar, groundnut oil, salt', ['Peanuts']);
      expect(r.hasDirectHit, isTrue);
      expect(AllergenMatcher.analyze('Ingredients: sugar, almonds', ['Peanuts']).hasDirectHit, isFalse);
      expect(AllergenMatcher.analyze('Ingredients: sugar, almonds', ['Nuts']).hasDirectHit, isTrue);
    });

    test('never removes a warning the old lists gave', () {
      AllergenDictionary.useForTest(dict);
      for (final (text, allergy) in [('wheat flour, malt', 'Gluten'), ('skimmed milk powder', 'Dairy'), ('may contain traces of peanuts', 'Peanuts'), ('shrimp paste', 'Shellfish'), ('contains soya lecithin', 'Soy')]) {
        expect(AllergenMatcher.analyze('Ingredients: $text', [allergy]).isSafe, isFalse, reason: text);
      }
    });

    test('plant milks do not trigger a dairy alert, a real milk next to them still does', () {
      AllergenDictionary.useForTest(dict);
      expect(AllergenMatcher.analyze('Ingredients: water, coconut milk, salt', ['Dairy']).hasDirectHit, isFalse);
      expect(AllergenMatcher.analyze('Ingredients: coconut milk, skimmed milk powder', ['Dairy']).hasDirectHit, isTrue);
    });
  });

  group('allergens of foods', () {
    FoodItem food(String name, List<String> allergens, {List<String> aliases = const []}) => FoodItem(
          id: name, name: name, aliases: aliases, icon: '', servingLabel: '1', grams: 100, kcal: 100, protein: 1, carbs: 1, fat: 1,
          allergens: allergens, meals: const [], role: 'bulk', tags: const [], source: 'indb',
        );

    test('only ever adds to the list a food already has', () {
      final out = FoodDatabase.withDictionaryAllergens([
        food('Paneer butter masala', []),
        food('Plain rice', []),
        food('Fish pie', ['fish', 'gluten']),
        food('Garlic naan', ['dairy']),
      ], dict);
      expect(out[0].allergens, ['dairy']);
      expect(out[1].allergens, isEmpty);
      expect(out[2].allergens, containsAll(['fish', 'gluten']));
      expect(out[3].allergens, containsAll(['dairy', 'gluten']));
    });

    test('no dictionary leaves the list untouched', () {
      final items = [food('Paneer', [])];
      expect(identical(FoodDatabase.withDictionaryAllergens(items, null), items), isTrue);
    });

    test('over the real food list nothing is lost and a good number of foods gain allergens', () {
      final all = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync(), bulkJson: File('assets/data/foods_bulk.json').readAsStringSync()).items;
      final enriched = FoodDatabase.withDictionaryAllergens(all, dict);
      var gained = 0;
      for (var i = 0; i < all.length; i++) {
        expect(enriched[i].allergens, containsAll(all[i].allergens), reason: all[i].name);
        if (enriched[i].allergens.length > all[i].allergens.length) gained++;
      }
      // ignore: avoid_print
      print('foods: ${all.length}, foods that gained at least one allergen from the dictionary: $gained');
      expect(enriched.length, all.length);
    });
  });
}
