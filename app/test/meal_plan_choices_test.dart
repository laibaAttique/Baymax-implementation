import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/food.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/screens/nutrition/nutrition_plan_screen.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/meal_plan_prefs.dart';
import 'package:app/services/plan_generator.dart';
import 'package:app/services/user_session.dart';
import 'package:app/theme/app_theme.dart';

HealthProfile _profile({String gender = 'Male', double weight = 80, String goal = 'Maintain & Stay Fit', List<String> allergies = const []}) {
  final dob = DateTime(DateTime.now().year - 30, 1, 1).toIso8601String().substring(0, 10);
  return HealthProfile(
    fullName: 'T', dob: dob, gender: gender, heightValue: 175, weightValue: weight, foodAllergies: allergies, primaryGoal: goal, activityLevel: 'Moderately Active', workoutFrequency: 3,
  );
}

void main() {
  late FoodDatabase db;
  const classifier = RuleBasedClassifier();

  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    db = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync(), bulkJson: File('assets/data/foods_bulk.json').readAsStringSync());
  });

  PersonalizedPlan gen(HealthProfile p, {int variant = 0, int? mealVariant, int? kcal}) => PlanGenerator(db).generate(p, classifier.classify(p), variant: variant, mealVariant: mealVariant, customKcal: kcal);

  group('regenerating the meals', () {
    test('changes the meals and leaves the workouts exactly as they were', () {
      final p = _profile();
      final a = gen(p, mealVariant: 0);
      final b = gen(p, mealVariant: 1);
      expect(b.nutrition.targetKcal, a.nutrition.targetKcal); // same calories
      final names = (PersonalizedPlan x) => [for (final m in x.nutrition.meals.values) for (final i in m) i.food.id];
      expect(names(b), isNot(names(a)));
      final workout = (PersonalizedPlan x) => [for (final d in x.week) d?.name ?? '-'];
      expect(workout(b), workout(a));
      final exercises = (PersonalizedPlan x) => [for (final d in x.week) for (final e in d?.exercises ?? const []) e.exercise.id];
      expect(exercises(b), exercises(a));
    });

    test('every new set is different from the one before, for several people', () {
      for (final p in [_profile(), _profile(gender: 'Female', weight: 58, goal: 'Lose Weight'), _profile(goal: 'Gain Muscle'), _profile(allergies: ['Dairy'])]) {
        final seen = <String>{};
        for (var v = 0; v < 6; v++) {
          final ids = [for (final m in gen(p, mealVariant: v).nutrition.meals.values) for (final i in m) i.food.id].join(',');
          seen.add(ids);
        }
        expect(seen.length, greaterThanOrEqualTo(5), reason: p.primaryGoal);
      }
    });
  });

  group('choosing your own calories', () {
    test('the range keeps to the safe floor and to 1,000 below / 500 above maintenance', () {
      final p = _profile();
      final (lo, hi) = MealPlanPrefs.range(p);
      expect(lo, greaterThanOrEqualTo(1500));
      expect(lo, greaterThanOrEqualTo(p.bmr.ceil()));
      expect(lo, greaterThanOrEqualTo((p.tdee - 1000).ceil()));
      expect(hi, (p.tdee + 500).floor());
      final woman = _profile(gender: 'Female', weight: 55);
      expect(MealPlanPrefs.range(woman).$1, greaterThanOrEqualTo(1200));
    });

    test('numbers are checked, with a reason the person can act on', () {
      final p = _profile();
      final (lo, hi) = MealPlanPrefs.range(p);
      expect(MealPlanPrefs.problem('abc', p), contains('whole number'));
      expect(MealPlanPrefs.problem('', p), contains('whole number'));
      expect(MealPlanPrefs.problem('${lo - 1}', p), contains('not recommended'));
      expect(MealPlanPrefs.problem('${hi + 1}', p), contains('more than'));
      expect(MealPlanPrefs.problem('$lo', p), isNull);
      expect(MealPlanPrefs.problem(' $hi ', p), isNull);
    });

    test('the plan is rebuilt for the chosen calories, with macros and meals that follow', () {
      final p = _profile();
      final base = gen(p);
      final (lo, hi) = MealPlanPrefs.range(p);
      final target = ((lo + hi) / 2).round();
      expect(target, isNot(base.nutrition.targetKcal));
      final own = gen(p, kcal: target);
      expect(own.nutrition.targetKcal, target);
      expect(own.nutrition.custom, isTrue);
      expect(own.nutrition.calorieNote, contains('chose this daily target yourself'));
      expect(base.nutrition.custom, isFalse);
      final macroKcal = own.nutrition.proteinG * 4 + own.nutrition.carbsG * 4 + own.nutrition.fatG * 9;
      expect(macroKcal, closeTo(target, target * 0.08));
      final mealKcal = own.nutrition.meals.values.expand((l) => l).fold(0.0, (s, i) => s + i.kcal);
      expect(mealKcal, inInclusiveRange(target * 0.6, target * 1.45));
    });

    test('a number outside the range is pulled back inside it, never used as it is', () {
      final p = _profile();
      final (lo, hi) = MealPlanPrefs.range(p);
      expect(gen(p, kcal: 900).nutrition.targetKcal, lo);
      expect(gen(p, kcal: 5000).nutrition.targetKcal, hi);
    });

    test('allergies and tag filters still apply at any calorie level', () {
      final p = _profile(allergies: ['Nuts', 'Dairy']);
      final (lo, hi) = MealPlanPrefs.range(p);
      for (final k in [lo, hi]) {
        for (final i in gen(p, kcal: k).nutrition.meals.values.expand((l) => l)) {
          expect(i.food.allergens.any(['nuts', 'dairy'].contains), isFalse, reason: i.food.name);
        }
      }
    });

    test('the stored form is read safely', () {
      expect(MealPlanPrefs.fromJson(null).variant, 0);
      expect(MealPlanPrefs.fromJson({'variant': 3, 'customKcal': 2100}).customKcal, 2100);
      expect(MealPlanPrefs.fromJson({'variant': 3, 'customKcal': 50}).customKcal, isNull); // outside the allowed numbers
      expect(MealPlanPrefs.fromJson({'variant': 'x'}).variant, 0);
      expect(MealPlanPrefs.none.copyWith(customKcal: 2000).copyWith(clearKcal: true).customKcal, isNull);
    });
  });

  group('logging the plan', () {
    late NutritionPlan plan;
    setUpAll(() => plan = gen(_profile()).nutrition);
    final day = DateTime(2026, 10, 22);

    test('a meal becomes one food-log entry per food, with the servings and nutrition the plan shows', () {
      final entries = NutritionPlanScreenEntries.of(plan, 'Lunch', day);
      final items = plan.meals['Lunch']!;
      expect(entries.length, items.length);
      for (var i = 0; i < items.length; i++) {
        expect(entries[i].name, items[i].food.name);
        expect(entries[i].date, '2026-10-22');
        expect(entries[i].meal, 'Lunch');
        expect(entries[i].unit, 'serving');
        expect(entries[i].quantity, closeTo(items[i].servings, 0.01));
        expect(entries[i].kcal, closeTo(items[i].kcal, 0.06));
        expect(entries[i].source, 'manual'); // one of the sources the database rules accept
      }
      final total = entries.fold(0.0, (s, e) => s + e.kcal);
      expect(total, closeTo(plan.mealKcal('Lunch'), 1.0));
    });
  });

  group('the screen', () {
    Future<void> pump(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(1170, 9000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => UserSession.instance.setProfile(_profile()));
      FoodDatabase.useForTest(db);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: screen));
      await tester.pumpAndSettle();
    }

    testWidgets('Regenerate meals calls the choice and says so', (tester) async {
      var calls = 0;
      await pump(tester, NutritionPlanScreen(onRegenerate: () async => ++calls > 0));
      await tester.tap(find.text('Regenerate meals'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.textContaining('another set of meals'), findsOneWidget);
    });

    testWidgets('a failed save is reported, not hidden', (tester) async {
      await pump(tester, NutritionPlanScreen(onRegenerate: () async => false));
      await tester.tap(find.text('Regenerate meals'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be saved'), findsOneWidget);
    });

    testWidgets('Set my calories checks the number and sends a valid one', (tester) async {
      int? chosen = -999;
      await pump(tester, NutritionPlanScreen(onSetKcal: (k) async {
        chosen = k;
        return true;
      }));
      await tester.tap(find.text('Set my calories'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '900');
      await tester.tap(find.text('Use this'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not recommended'), findsOneWidget);
      expect(chosen, -999);
      final p = UserSession.instance.profile!;
      final (lo, _) = MealPlanPrefs.range(p);
      await tester.enterText(find.byType(TextField), '${lo + 100}');
      await tester.tap(find.text('Use this'));
      await tester.pumpAndSettle();
      expect(chosen, lo + 100);
      expect(find.textContaining('Your plan now uses ${lo + 100} kcal'), findsOneWidget);
    });

    testWidgets('Log this meal sends the meal to the food log once, and asks before logging it twice', (tester) async {
      final logged = <List<FoodEntry>>[];
      await pump(tester, NutritionPlanScreen(clock: () => DateTime(2026, 10, 22, 12), onLog: (e) async => logged.add(e)));
      await tester.tap(find.text('Log this meal').at(1)); // Lunch
      await tester.pumpAndSettle();
      expect(logged.length, 1);
      expect(logged.single.every((e) => e.meal == 'Lunch' && e.date == '2026-10-22'), isTrue);
      expect(find.text('Logged today'), findsOneWidget);
      await tester.tap(find.text('Logged today'));
      await tester.pumpAndSettle();
      expect(find.text('Log again?'), findsOneWidget);
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(logged.length, 1);
    });

    testWidgets('Log my whole day logs every meal', (tester) async {
      final logged = <List<FoodEntry>>[];
      await pump(tester, NutritionPlanScreen(clock: () => DateTime(2026, 10, 22, 12), onLog: (e) async => logged.add(e)));
      await tester.tap(find.text('Log my whole day'));
      await tester.pumpAndSettle();
      expect(logged.length, 1);
      expect({for (final e in logged.single) e.meal}, {'Breakfast', 'Lunch', 'Dinner', 'Snack'});
      expect(find.textContaining('Logged your day'), findsOneWidget);
    });
  });
}

/// The screen's own conversion, called without a widget.
class NutritionPlanScreenEntries {
  static List<FoodEntry> of(NutritionPlan n, String meal, DateTime day) => entriesForTest(n, meal, day);
}
