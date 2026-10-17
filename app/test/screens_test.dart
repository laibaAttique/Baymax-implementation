import 'package:flutter/material.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/workout_readiness.dart';
import 'package:app/screens/allergy/allergen_result_screen.dart';
import 'package:app/screens/health_profiling/bmi_result.dart';
import 'package:app/screens/health_profiling/health_classification.dart';
import 'package:app/screens/nutrition/nutrition_plan_screen.dart';
import 'package:app/screens/workout_and_exercise/exercise_detail.dart';
import 'package:app/screens/workout_and_exercise/workout_plan.dart';
import 'package:app/services/allergen_matcher.dart';
import 'package:app/services/user_session.dart';

HealthProfile _profile({List<String> conditions = const [], List<String> allergies = const ['Dairy', 'Nuts']}) {
  return HealthProfile(
    fullName: 'Aamna Khan',
    dob: '2000-03-15',
    gender: 'Female',
    heightValue: 165,
    weightValue: 72,
    medicalConditions: conditions,
    foodAllergies: allergies,
    primaryGoal: 'Lose Weight',
    activityLevel: 'Lightly Active',
    workoutFrequency: 4,
  );
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1170, 2532); // 390x844 logical @3x
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: screen));
  await tester.pumpAndSettle();
}

void main() {
  Future<void> setUpSession(WidgetTester tester, HealthProfile p) async {
    await tester.runAsync(() => UserSession.instance.setProfile(p));
  }

  tearDown(() => UserSession.instance.clear());

  testWidgets('BMI result shows computed BMI/BMR/calories (no overflow)', (tester) async {
    final p = _profile();
    await setUpSession(tester, p);
    await _pump(tester, BmiResult(profile: p));

    expect(tester.takeException(), isNull);
    expect(find.text(p.bmi.toStringAsFixed(1)), findsOneWidget);
    expect(find.textContaining('Mifflin-St Jeor'), findsOneWidget);
    expect(find.text('Deficit'), findsOneWidget);
  });

  testWidgets('Health classification screen renders category and risk factors', (tester) async {
    await setUpSession(tester, _profile(conditions: ['Hypertension']));
    await _pump(tester, const HealthClassification());

    expect(tester.takeException(), isNull);
    expect(find.text('AT-RISK'), findsOneWidget);
    expect(find.textContaining('Hypertension'), findsWidgets);
    expect(find.text('View workout plan'), findsOneWidget);
  });

  testWidgets('Workout plan with a heart condition is held back until readiness is answered (Module 4 screening)', (tester) async {
    await setUpSession(tester, _profile(conditions: ['Heart Disease']));
    await _pump(tester, const WorkoutPlan());
    expect(tester.takeException(), isNull);
    expect(find.text('A few answers are needed first'), findsOneWidget);
    expect(find.textContaining('SCR-CARDIAC-UNANSWERED'), findsOneWidget);
    expect(find.text('Dynamic Warm-Up'), findsNothing);

    UserSession.instance.readiness = const WorkoutReadiness(clearance: false);
    await setUpSession(tester, _profile(conditions: ['Heart Disease']));
    await tester.pumpAndSettle();
    expect(find.textContaining('clearance comes first'), findsOneWidget);
  });

  testWidgets('Workout plan lists exercises, shows medical notes and can switch days', (tester) async {
    UserSession.instance.readiness = const WorkoutReadiness(clearance: true);
    await setUpSession(tester, _profile(conditions: ['Heart Disease']));
    await _pump(tester, const WorkoutPlan());

    expect(tester.takeException(), isNull);
    expect(find.text('Your workout plan'), findsOneWidget);
    expect(find.text('Cardiac'), findsOneWidget);
    expect(find.text('Dynamic Warm-Up'), findsWidgets);

    // Tap a rest day (Sunday) – cardiac plans never train 7 days.
    await tester.tap(find.text('S').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('rest day'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Exercise detail renders technique steps', (tester) async {
    await setUpSession(tester, _profile());
    final day = UserSession.instance.plan!.week.whereType<WorkoutDay>().first;
    await _pump(tester, ExerciseDetail(planned: day.exercises[1]));

    expect(tester.takeException(), isNull);
    expect(find.text('Technique'), findsOneWidget);
    expect(find.text('Start exercise'), findsOneWidget);
  });

  testWidgets('Nutrition plan shows macros and no allergens', (tester) async {
    final p = _profile();
    await setUpSession(tester, p);
    await _pump(tester, const NutritionPlanScreen());

    expect(tester.takeException(), isNull);
    expect(find.text('${UserSession.instance.plan!.nutrition.targetKcal}'), findsOneWidget);
    expect(find.text('Dairy products'), findsOneWidget); // in "Foods to avoid"
    await tester.scrollUntilVisible(find.text('Pro tips'), 300, scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Allergen result screen raises an alert dialog when an allergen is found', (tester) async {
    final result = AllergenMatcher.analyze(
      'Ingredients: Wheat flour, sugar, milk powder, peanut butter, salt',
      ['Dairy', 'Nuts'],
    );
    await _pump(tester, AllergenResultScreen(result: result));

    expect(tester.takeException(), isNull);
    expect(find.text('ALLERGEN DETECTED'), findsOneWidget);
    await tester.tap(find.text('OK, Got It'));
    await tester.pumpAndSettle();
    expect(find.text('2 allergens found'), findsOneWidget);
    expect(find.text('milk powder'), findsOneWidget);
  });

  testWidgets('Allergen result screen shows safe state without a dialog', (tester) async {
    final result = AllergenMatcher.analyze('Ingredients: rice, salt, water', ['Dairy']);
    await _pump(tester, AllergenResultScreen(result: result));

    expect(tester.takeException(), isNull);
    expect(find.text('ALLERGEN DETECTED'), findsNothing);
    expect(find.text('No allergens found'), findsOneWidget);
  });
}
