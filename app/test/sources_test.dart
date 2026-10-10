import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/food.dart';
import 'package:app/services/chatbot_engine.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/catalog_service.dart';
import 'package:app/services/food_database.dart';

void main() {
  setUpAll(() => ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync()));

  group('Exercise library data', () {
    test('every entry is complete and its provenance is consistent', () {
      final all = [...ExerciseLibrary.all, ExerciseLibrary.warmUp, ExerciseLibrary.coolDown];
      expect(all.map((e) => e.id).toSet().length, all.length, reason: 'ids must be unique');
      const groups = {'cardio', 'legs', 'push', 'back', 'core', 'mobility'};
      for (final e in all) {
        expect(groups, contains(e.group), reason: e.name);
        expect(e.steps.length, greaterThanOrEqualTo(2), reason: '${e.name} needs technique steps');
        expect(e.muscles, isNotEmpty, reason: e.name);
        expect(['team', 'free-exercise-db'], contains(e.techniqueSource), reason: e.name);
        if (e.techniqueSource == 'free-exercise-db') {
          expect(e.referenceId, isNotNull, reason: '${e.name} claims a dataset source but has no reference id');
          expect(['exact', 'related'], contains(e.referenceMatch), reason: e.name);
        } else {
          expect(e.referenceId, isNull, reason: e.name);
        }
      }
    });

    test('safety tags exist where the rules depend on them', () {
      final byId = {for (final e in ExerciseLibrary.all) e.id: e};
      expect(byId['plank']!.tags, contains('isometric'));
      expect(byId['wall_sit']!.tags, contains('isometric'));
      expect(byId['burpees']!.tags, containsAll(['hiit', 'plyo']));
      expect(byId['single_leg_balance']!.tags, contains('balance'));
      expect(byId['burpees']!.impact, 'high');
    });

    test('every plan template group has exercises to draw from', () {
      for (final g in ['cardio', 'legs', 'push', 'back', 'core', 'mobility']) {
        expect(ExerciseLibrary.all.where((e) => e.group == g), isNotEmpty, reason: g);
      }
    });

    test('the Exercise model survives a JSON round trip', () {
      final e = ExerciseLibrary.byId('pushup')!;
      final copy = Exercise.fromJson(e.toJson());
      expect(copy.met, e.met);
      expect(copy.compendium, e.compendium);
      expect(copy.referenceId, 'Pushups');
      expect(copy.steps, e.steps);
    });
  });

  group('Exercise energy values come from the Compendium', () {
    List<Exercise> all() => [...ExerciseLibrary.all, ExerciseLibrary.warmUp, ExerciseLibrary.coolDown];

    test('every exercise cites a Compendium code and has a plausible MET', () {
      for (final e in all()) {
        expect(e.compendium, matches(RegExp(r'^\d{5}\*?$')), reason: '${e.name} needs a Compendium code');
        expect(e.met, inInclusiveRange(1.5, 9.0), reason: e.name);
      }
    });

    test('spot-check against the published 2024 Compendium', () {
      double met(String id) => ExerciseLibrary.byId(id)!.met;
      expect(met('jumping_jacks'), 7.5); // 02020 vigorous calisthenics
      expect(met('burpees'), 7.5); // 02020
      expect(met('pushup'), 3.8); // 02022 moderate calisthenics
      expect(met('plank'), 2.8); // 02024 light calisthenics
      expect(met('brisk_walk'), 3.8); // 17190 walking 2.8–3.4 mph
      expect(met('squat'), 3.0); // 02056 body-weight resistance, general
      expect(ExerciseLibrary.byId('cooldown')!.met, 2.3); // 02101 stretching, mild
    });

    test('exercises not listed in the Compendium are flagged as approximations', () {
      for (final id in ['march', 'step_ups', 'shadow_boxing', 'high_knees', 'mountain_climbers', 'single_leg_balance']) {
        expect(ExerciseLibrary.byId(id)!.compendium.endsWith('*'), isTrue, reason: id);
      }
    });
  });

  group('Food provenance', () {
    late FoodDatabase db;
    setUpAll(() => db = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync()));

    test('every local food declares where its numbers come from', () {
      for (final f in db.items) {
        expect(['usda', 'estimate'], contains(f.source), reason: f.name);
        if (f.fromUsda) expect(f.fdcId, isNotNull, reason: '${f.name} is marked USDA but has no FDC id');
      }
    });

    test('provenance reference is stored with a logged entry', () {
      final usda = FoodItem(
        id: 'usda_175254', name: 'Lentils', aliases: const [], icon: '🍽️', servingLabel: '100 g', grams: 100,
        kcal: 114, protein: 9, carbs: 19.5, fat: 0.4, allergens: const [], meals: const [], role: 'main', tags: const [],
        source: 'usda', fdcId: '175254',
      );
      expect(usda.ref, 'usda:175254');
      expect(usda.sourceLabel, 'USDA FoodData Central');
      final entry = FoodEntry.fromJson({'meal': 'Lunch', 'name': 'x', 'kcal': 1, 'ref': usda.ref, 'date': '2026-10-12'});
      expect(entry.ref, 'usda:175254');
      expect(db.items.first.ref, 'estimate'); // until verified against USDA
    });
  });

  group('Firestore food catalogue', () {
    test('refreshes only when the server catalogue changed', () {
      bool refresh(int? cached, int? server, bool has) =>
          CatalogService.needsRefresh(cachedVersion: cached, serverVersion: server, cacheHasItems: has);

      expect(refresh(null, 5, false), isTrue, reason: 'first run');
      expect(refresh(5, 5, true), isFalse, reason: 'up to date');
      expect(refresh(4, 5, true), isTrue, reason: 'server has a newer version');
      expect(refresh(5, null, true), isFalse, reason: 'offline: keep using the cached copy');
      expect(refresh(5, null, false), isTrue, reason: 'nothing cached, try the server');
    });

    test('a Firestore document converts to a food item', () {
      // Shape of the documents written by tools/seed_firestore_foods.js
      final doc = {
        'name': 'Lentils', 'aliases': ['daal'], 'icon': '🍲', 'serving': '1 bowl', 'grams': 200, 'kcal': 230,
        'protein': 14, 'carbs': 33, 'fat': 5, 'allergens': <String>[], 'meals': ['lunch'], 'role': 'main',
        'tags': ['lean'], 'source': 'usda', 'fdcId': '175254',
      };
      final item = FoodItem.fromJson({...doc, 'id': 'daal'});
      expect(item.id, 'daal');
      expect(item.kcal, 230);
      expect(item.fromUsda, isTrue);
      expect(item.ref, 'usda:175254');
    });

    test('the bundled fallback is labelled as such', () {
      final db = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
      expect(db.origin, CatalogOrigin.bundled);
      expect(db.originLabel, contains('offline copy'));
    });
  });

  test('chatbot explains where its numbers come from', () {
    final r = const ChatbotEngine().respond('where do your numbers come from?', ChatContext(profile: HealthProfile()));
    expect(r.intent, 'faq');
    expect(r.text, contains('USDA'));
    expect(r.actions.any((a) => a.type == 'sources'), isTrue);
  });
}
