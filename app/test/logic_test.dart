import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/services/allergen_matcher.dart';
import 'package:app/services/chatbot_engine.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/food_parser.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/plan_generator.dart';
import 'package:app/utils/health_calc.dart';

HealthProfile profile({
  String gender = 'Male',
  double height = 175,
  double weight = 70,
  int age = 30,
  List<String> conditions = const [],
  List<String> allergies = const [],
  String goal = 'Maintain & Stay Fit',
  String activity = 'Moderately Active',
  int freq = 4,
}) {
  final dob = DateTime(DateTime.now().year - age, 1, 1).toIso8601String().substring(0, 10);
  return HealthProfile(
    fullName: 'Test User',
    dob: dob,
    gender: gender,
    heightValue: height,
    weightValue: weight,
    medicalConditions: conditions,
    foodAllergies: allergies,
    primaryGoal: goal,
    activityLevel: activity,
    workoutFrequency: freq,
  );
}

void main() {
  late FoodDatabase db;
  const classifier = RuleBasedClassifier();

  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    db = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
  });

  group('HealthCalc (Module 1)', () {
    test('BMI and WHO category', () {
      expect(HealthCalc.bmi(70, 175), closeTo(22.86, 0.01));
      expect(HealthCalc.whoCategory(17), 'Underweight');
      expect(HealthCalc.whoCategory(22), 'Normal');
      expect(HealthCalc.whoCategory(27), 'Overweight');
      expect(HealthCalc.whoCategory(32), 'Obese (Class I)');
      expect(HealthCalc.whoCategory(42), 'Obese (Class III)');
    });

    test('Mifflin-St Jeor BMR', () {
      expect(HealthCalc.bmr(gender: 'Male', weightKg: 70, heightCm: 175, age: 30), closeTo(1648.75, 0.01));
      expect(HealthCalc.bmr(gender: 'Female', weightKg: 60, heightCm: 165, age: 25), closeTo(1345.25, 0.01));
    });

    test('unit conversion feeds BMI correctly', () {
      final p = profile(height: 5.75, weight: 154);
      p.heightUnit = 'ft';
      p.weightUnit = 'lbs';
      expect(p.heightCm, closeTo(175.26, 0.01));
      expect(p.weightKg, closeTo(69.85, 0.01));
      expect(p.bmi, closeTo(22.7, 0.1));
    });

    test('deficit never drops below the safe floor and is skipped when underweight', () {
      final t = HealthCalc.calorieTargets(bmr: 1100, tdee: 1500, gender: 'Female', bmi: 22);
      expect(t.deficit, 1200);
      expect(t.safetyNote, isNotNull);
      final u = HealthCalc.calorieTargets(bmr: 1300, tdee: 1800, gender: 'Female', bmi: 17);
      expect(u.deficit, u.maintain);
    });

    test('age from DOB', () {
      expect(HealthCalc.ageFromDob('2000-06-15', now: DateTime(2026, 6, 14)), 25);
      expect(HealthCalc.ageFromDob('2000-06-15', now: DateTime(2026, 6, 15)), 26);
      expect(HealthCalc.ageFromDob(''), isNull);
    });

    test('diabetic macros cap carbs at 40%', () {
      final m = HealthCalc.macros(kcal: 2000, weightKg: 70, goal: 'Maintain & Stay Fit', diabetic: true);
      expect(m.carbsG * 4 / 2000, lessThanOrEqualTo(0.401));
    });
  });

  group('Classifier (Module 2)', () {
    String cat(HealthProfile p) => classifier.classify(p).category;

    test('WHO BMI categories', () {
      expect(cat(profile(weight: 70)), 'Healthy');
      expect(cat(profile(weight: 85)), 'Overweight'); // BMI 27.8
      expect(cat(profile(weight: 100)), 'Obese'); // BMI 32.7
    });

    test('medical conditions override BMI', () {
      expect(cat(profile(weight: 100, conditions: ['Heart Disease'])), 'Cardiac');
      expect(cat(profile(weight: 100, conditions: ['Diabetes'])), 'Diabetic');
      expect(cat(profile(conditions: ['Heart Disease', 'Diabetes'])), 'Cardiac');
      expect(cat(profile(conditions: ['Hypertension'])), 'At-Risk');
      expect(cat(profile(weight: 50)), 'At-Risk'); // BMI 16.3 underweight
    });

    test('risk levels and factors', () {
      final r = classifier.classify(profile(weight: 100, conditions: ['Hypertension'], allergies: ['Dairy']));
      expect(r.category, 'At-Risk');
      expect(r.riskLevel, 'High');
      expect(r.riskFactors, containsAll(['Hypertension', 'Dairy allergy']));
    });
  });

  group('Plan generator (Module 3)', () {
    PersonalizedPlan planFor(HealthProfile p, {int variant = 0}) =>
        PlanGenerator(db).generate(p, classifier.classify(p), variant: variant);

    Iterable<Exercise> exercisesOf(PersonalizedPlan plan) =>
        plan.week.whereType<WorkoutDay>().expand((d) => d.exercises).map((e) => e.exercise);

    test('cardiac plan: low intensity, no high impact / HIIT / isometrics, max 4 days', () {
      final plan = planFor(profile(conditions: ['Heart Disease'], goal: 'Lose Weight', freq: 6));
      expect(plan.category, 'Cardiac');
      expect(plan.intensity, 'Low');
      expect(plan.workoutDays, lessThanOrEqualTo(4));
      for (final e in exercisesOf(plan)) {
        expect(e.impact, 'low', reason: e.name);
        expect(e.tags.contains('hiit'), isFalse, reason: e.name);
        expect(e.tags.contains('isometric'), isFalse, reason: e.name);
      }
      expect(plan.restrictionNotes.join(' '), contains('doctor'));
    });

    test('obese plan has no high-impact exercises', () {
      final plan = planFor(profile(weight: 105, goal: 'Lose Weight', freq: 5));
      expect(plan.category, 'Obese');
      expect(exercisesOf(plan).where((e) => e.impact == 'high'), isEmpty);
      expect(plan.workoutDays, lessThanOrEqualTo(5));
    });

    test('hypertension keeps static holds short (20 s cap) and removes HIIT / high impact', () {
      final plan = planFor(profile(conditions: ['Hypertension'], goal: 'Gain Muscle', freq: 5));
      final planned = plan.week.whereType<WorkoutDay>().expand((d) => d.exercises);
      final holds = planned.where((p) => p.exercise.tags.contains('isometric')).toList();
      expect(holds, isNotEmpty, reason: 'holds are capped, not banned');
      for (final h in holds) {
        expect(h.seconds, lessThanOrEqualTo(20), reason: h.exercise.name);
      }
      for (final p in planned) {
        expect(p.exercise.tags.contains('hiit'), isFalse, reason: p.exercise.name);
        expect(p.exercise.impact, 'low', reason: p.exercise.name);
      }
      expect(plan.restrictionNotes.join(' '), contains('20 seconds'));
    });

    test('balance training is added from age 65 (WHO), not before', () {
      bool hasBalance(int age) {
        final plan = planFor(profile(age: age, goal: 'Maintain & Stay Fit', activity: 'Lightly Active'));
        return exercisesOf(plan).any((e) => e.tags.contains('balance'));
      }
      expect(hasBalance(64), isFalse);
      expect(hasBalance(65), isTrue);
    });

    test('cardiac plans contain no static holds at all', () {
      final plan = planFor(profile(conditions: ['Heart Disease'], goal: 'Gain Muscle', freq: 4));
      expect(exercisesOf(plan).where((e) => e.tags.contains('isometric')), isEmpty);
    });

    test('fit healthy user can get high-impact work and requested frequency', () {
      final plan = planFor(profile(goal: 'Lose Weight', activity: 'Very Active', freq: 5));
      expect(plan.intensity, 'High');
      expect(plan.workoutDays, 5);
      expect(exercisesOf(plan).any((e) => e.impact == 'high'), isTrue);
    });

    test('every workout day has warm-up first and cool-down last', () {
      final plan = planFor(profile(goal: 'Gain Muscle', freq: 4));
      for (final d in plan.week.whereType<WorkoutDay>()) {
        expect(d.exercises.first.exercise.id, 'warmup');
        expect(d.exercises.last.exercise.id, 'cooldown');
        expect(d.durationMin, greaterThan(10));
        expect(d.kcal(70), greaterThan(0));
      }
    });

    test('regenerating changes the exercises (FE-7)', () {
      final p = profile(goal: 'Gain Muscle', freq: 4);
      final a = planFor(p, variant: 0);
      final b = planFor(p, variant: 1);
      String sig(PersonalizedPlan x) => x.week.map((d) => d?.exercises.map((e) => e.exercise.id).join(',')).join('|');
      expect(sig(a), isNot(sig(b)));
    });

    test('nutrition: macros add up to the calorie target', () {
      final p = profile(goal: 'Lose Weight');
      final n = planFor(p).nutrition;
      final fromMacros = n.proteinG * 4 + n.carbsG * 4 + n.fatG * 9;
      expect((fromMacros - n.targetKcal).abs(), lessThan(40));
      expect(n.targetKcal, p.calorieTargets.deficit);
    });

    test('meal plan never contains the user\'s allergens', () {
      final p = profile(allergies: ['Dairy', 'Gluten', 'Eggs', 'Nuts'], goal: 'Lose Weight');
      for (var v = 0; v < 6; v++) {
        final n = planFor(p, variant: v).nutrition;
        for (final items in n.meals.values) {
          for (final i in items) {
            expect(i.food.conflictsWith(p.allergies), isEmpty, reason: '${i.food.name} in variant $v');
          }
        }
        expect(n.meals['Lunch'], isNotEmpty);
      }
    });

    test('diabetic meal plan excludes high-sugar and refined foods', () {
      final p = profile(conditions: ['Diabetes']);
      for (var v = 0; v < 6; v++) {
        for (final items in planFor(p, variant: v).nutrition.meals.values) {
          for (final i in items) {
            expect(i.food.tags.contains('highSugar'), isFalse, reason: i.food.name);
            expect(i.food.tags.contains('refined'), isFalse, reason: i.food.name);
          }
        }
      }
    });

    test('meal calories land near the daily target', () {
      final n = planFor(profile(weight: 75)).nutrition;
      final total = n.meals.keys.fold(0.0, (s, m) => s + n.mealKcal(m));
      expect(total, inInclusiveRange(n.targetKcal * 0.75, n.targetKcal * 1.25));
    });
  });

  group('Food parsing (Module 7)', () {
    late FoodParser parser;
    setUp(() => parser = FoodParser(db));

    test('counts, units and multiple foods', () {
      final r = parser.parse('2 rotis and a bowl of daal');
      expect(r.length, 2);
      expect(r[0].item!.id, 'roti');
      expect(r[0].servings, 2);
      expect(r[0].kcal, closeTo(220, 0.5));
      expect(r[1].item!.id, 'daal');
      expect(r[1].servings, 1);
    });

    test('gram quantities scale by serving weight', () {
      final r = parser.parse('150g grilled chicken breast');
      expect(r.single.item!.id, 'grilled_chicken');
      expect(r.single.kcal, closeTo(248, 1));
      final r2 = parser.parse('300 g chicken breast');
      expect(r2.single.kcal, closeTo(496, 2));
    });

    test('fractions, sizes, plurals and aliases', () {
      expect(parser.parse('half a cup of rice').single.servings, 0.5);
      expect(parser.parse('1 large banana').single.servings, 1.3);
      expect(parser.parse('3 eggs').single.item!.id, 'boiled_egg');
      expect(parser.parse('1 glass doodh').single.item!.id, 'milk');
      expect(parser.parse('I had chicken biryani for lunch').single.item!.id, 'chicken_biryani');
    });

    test('commas, "and" and "+" separate foods; unknown foods are reported', () {
      final r = parser.parse('2 eggs, toast + green tea and blorptastic');
      expect(r.map((p) => p.item?.id), ['boiled_egg', 'white_bread', 'green_tea', null]);
    });

    test('search finds foods by partial and misspelled names', () {
      expect(db.search('chick', limit: 20).map((f) => f.id), contains('grilled_chicken'));
      expect(db.search('biryani').first.id, 'chicken_biryani');
      expect(db.match('banan')?.id, 'banana');
    });
  });

  group('Allergen matcher (Module 8)', () {
    const label = 'INGREDIENTS: Wheat flour, sugar, milk powder, soy oil, peanut butter, salt, emulsifier (E322).';

    test('finds all four allergens in a typical label', () {
      final r = AllergenMatcher.analyze(label, ['Dairy', 'Nuts', 'Gluten', 'Soy', 'Shellfish']);
      expect(r.allergensFound, {'Dairy', 'Nuts', 'Gluten', 'Soy'});
      expect(r.isSafe, isFalse);
      final flagged = r.ingredients.where((i) => i.flagged).map((i) => i.text).toList();
      expect(flagged, containsAll(['Wheat flour', 'milk powder', 'soy oil', 'peanut butter']));
      expect(r.ingredients.firstWhere((i) => i.text == 'sugar').flagged, isFalse);
    });

    test('only checks the user\'s own allergies', () {
      final r = AllergenMatcher.analyze(label, ['Shellfish']);
      expect(r.isSafe, isTrue);
    });

    test('does not flag look-alike ingredients', () {
      final r = AllergenMatcher.analyze(
        'Ingredients: coconut milk, cocoa butter, rice flour, nutmeg, eggplant, almond milk',
        ['Dairy', 'Gluten', 'Nuts', 'Eggs'],
      );
      expect(r.allergensFound, {'Nuts'}, reason: 'only almond milk contains a tree nut');
    });

    test('tolerates OCR digit/letter confusion and small typos', () {
      final digit = AllergenMatcher.analyze('Ingredients: sugar, mi1k solids, salt', ['Dairy']);
      expect(digit.allergensFound, {'Dairy'});
      final typo = AllergenMatcher.analyze('Ingredients: sugar, buttter, salt', ['Dairy']);
      expect(typo.allergensFound, {'Dairy'});
      expect(typo.ingredients.firstWhere((i) => i.flagged).hits.single.exact, isFalse);
    });

    test('"may contain" statements are reported separately as trace risk', () {
      final r = AllergenMatcher.analyze('Ingredients: rice, salt. May contain traces of peanuts and milk.', ['Nuts', 'Dairy']);
      expect(r.hasDirectHit, isFalse);
      expect(r.traceAllergens, {'Nuts', 'Dairy'});
      expect(r.isSafe, isFalse);
    });

    test('handles multi-line OCR text and plurals', () {
      final r = AllergenMatcher.analyze('Nutrition facts\nCalories 120\nIngredients:\nCorn, shrimps,\nsalt', ['Shellfish']);
      expect(r.allergensFound, {'Shellfish'});
    });
  });

  group('Chatbot (Module 12)', () {
    const bot = ChatbotEngine();
    late ChatContext ctx;

    setUp(() {
      final p = profile(allergies: ['Dairy'], goal: 'Lose Weight');
      final cls = classifier.classify(p);
      ctx = ChatContext(
        profile: p,
        classification: cls,
        plan: PlanGenerator(db).generate(p, cls),
        db: db,
        consumedKcal: 600,
        now: DateTime(2026, 10, 12, 13), // Monday lunchtime
      );
    });

    test('detects intents', () {
      expect(bot.respond('hello', ctx).intent, 'greeting');
      expect(bot.respond('what is my bmi', ctx).intent, 'bmi');
      expect(bot.respond('how many calories should I eat', ctx).intent, 'calorie_target');
      expect(bot.respond('calories left today?', ctx).intent, 'remaining');
      expect(bot.respond("what's my workout today", ctx).intent, 'workout_today');
      expect(bot.respond('thanks!', ctx).intent, 'thanks');
    });

    test('answers calorie questions with real numbers', () {
      final bmi = bot.respond('whats my bmi', ctx).text;
      expect(bmi, contains('22.9'));
      final target = bot.respond('how many calories should I eat', ctx).text;
      expect(target, contains('${ctx.profile!.dailyCalorieTarget}'));
      final left = bot.respond('how many calories left', ctx).text;
      expect(left, contains('600'));
    });

    test('looks up foods', () {
      final r = bot.respond('How many calories in 2 rotis and daal?', ctx);
      expect(r.intent, 'calorie_lookup');
      expect(r.text, contains('450 kcal')); // 220 + 230
    });

    test('suggests meals that avoid the user\'s allergens', () {
      final r = bot.respond('what should I eat for lunch', ctx);
      expect(r.intent, 'meal');
      expect(r.text, contains('Lunch'));
      for (final item in ctx.plan!.nutrition.meals['Lunch']!) {
        expect(item.food.allergens.contains('dairy'), isFalse);
      }
    });

    test('checks whether a food is safe for the user\'s allergies', () {
      expect(bot.respond('can I eat butter chicken?', ctx).text, contains('🚫'));
      expect(bot.respond('can I eat grilled chicken?', ctx).text, contains('✅'));
    });

    test('explains how to do an exercise', () {
      final r = bot.respond('how do I do push ups', ctx);
      expect(r.intent, 'exercise_howto');
      expect(r.text, contains('Push-Ups'));
    });

    test('recommends a doctor for symptoms (FR-4) and treats emergencies urgently', () {
      final mild = bot.respond('my knee hurts after squats', ctx);
      expect(mild.intent, 'health_concern');
      expect(mild.actions.any((a) => a.type == 'consult'), isTrue);
      final urgent = bot.respond('I have chest pain', ctx);
      expect(urgent.intent, 'emergency');
      expect(urgent.text, contains('emergency'));
    });

    test('recommends a doctor for risky topics when the profile is high-risk', () {
      final p = profile(conditions: ['Diabetes']);
      final cls = classifier.classify(p);
      final c = ChatContext(profile: p, classification: cls, db: db);
      final r = bot.respond('should I try intermittent fasting?', c);
      expect(r.intent, 'doctor_recommended');
    });

    test('answers FAQs and falls back politely', () {
      expect(bot.respond('how do I log food', ctx).intent, 'faq');
      expect(bot.respond('what is bmi', ctx).intent, 'faq');
      expect(bot.respond('asdfgh qwerty', ctx).intent, 'fallback');
    });

    test('asks for profiling when there is no profile', () {
      final r = bot.respond('what is my bmi', ChatContext(db: db));
      expect(r.text, contains('profile'));
    });
  });
}
