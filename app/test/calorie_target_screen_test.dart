import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/screens/nutrition/calorie_target_screen.dart';
import 'package:app/services/calorie_optimizer.dart';
import 'package:app/services/user_session.dart';

HealthProfile _profile({double weight = 80, List<String> conditions = const []}) => HealthProfile(
      fullName: 'Test User',
      dob: '1995-05-05',
      gender: 'Male',
      heightValue: 175,
      weightValue: weight,
      medicalConditions: conditions,
      foodAllergies: const [],
      primaryGoal: 'Lose Weight',
      activityLevel: 'Lightly Active',
      workoutFrequency: 3,
    );

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.light(), home: screen));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => UserSession.instance.clear());

  group('the plan follows the estimate', () {
    test('an adapted estimate changes the daily target, a changed weight drops it again', () async {
      final p = _profile();
      await UserSession.instance.setProfile(p);
      final formulaTarget = UserSession.instance.plan!.nutrition.targetKcal;
      expect(formulaTarget, p.dailyCalorieTarget);

      UserSession.instance.calorieEstimate = CalorieEstimate(status: EstimateStatus.adapted, priorTdee: p.tdee, tdee: p.tdee + 300, reason: 'x');
      await UserSession.instance.setProfile(p);
      expect(UserSession.instance.plan!.nutrition.targetKcal, closeTo(formulaTarget + 300, 1));

      // a new weight changes the formula value, so the old estimate is discarded rather than reused
      p.weightValue = 76;
      await UserSession.instance.setProfile(p);
      expect(UserSession.instance.calorieEstimate, isNull);
      expect(UserSession.instance.plan!.nutrition.targetKcal, p.dailyCalorieTarget);
    });

    test('macros and meals follow the new target', () async {
      final p = _profile();
      await UserSession.instance.setProfile(p);
      final before = UserSession.instance.plan!.nutrition;
      UserSession.instance.calorieEstimate = CalorieEstimate(status: EstimateStatus.adapted, priorTdee: p.tdee, tdee: p.tdee + 300, reason: 'x');
      await UserSession.instance.setProfile(p);
      final after = UserSession.instance.plan!.nutrition;
      expect(after.targetKcal, greaterThan(before.targetKcal));
      expect(after.carbsG, greaterThanOrEqualTo(before.carbsG));
    });

    test('a user with diabetes keeps the formula target even if an estimate is present', () async {
      final p = _profile(conditions: ['Diabetes']);
      await UserSession.instance.setProfile(p);
      final formula = UserSession.instance.plan!.nutrition.targetKcal;
      UserSession.instance.calorieEstimate = CalorieEstimate(status: EstimateStatus.adapted, priorTdee: p.tdee, tdee: p.tdee + 300, reason: 'x');
      await UserSession.instance.setProfile(p);
      expect(UserSession.instance.plan!.nutrition.targetKcal, formula);
    });
  });

  testWidgets('screen: formula only, shows what is still needed and saves a weight', (tester) async {
    double? saved;
    final est = CalorieEstimate(
        status: EstimateStatus.formulaOnly, priorTdee: 2400, tdee: 2400, reason: 'Log your weight at least 4 times over 14+ days to personalise your target (so far 2).', weighIns: 2, completeDays: 3);
    await _pump(
      tester,
      CalorieTargetScreen(
        loader: () async => CalorieTargetData(estimate: est, weights: const [], targetKcal: 1900, formulaKcal: 1900),
        onSave: (kg) async => saved = kg,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('1900 kcal'), findsOneWidget);
    expect(find.textContaining('not enough of your data yet'), findsOneWidget);
    expect(find.textContaining('2 of 4 needed'), findsOneWidget);
    expect(find.textContaining('3 of 10 needed'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '79,4');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, 79.4);
  });

  testWidgets('screen: rejects an impossible weight', (tester) async {
    double? saved;
    await _pump(
      tester,
      CalorieTargetScreen(
        loader: () async => const CalorieTargetData(estimate: null, weights: [], targetKcal: 2000, formulaKcal: 2000),
        onSave: (kg) async => saved = kg,
      ),
    );
    await tester.enterText(find.byType(TextField), '5');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(saved, isNull);
    expect(find.textContaining('between 20 and 400'), findsOneWidget);
  });

  testWidgets('screen: an adapted target explains itself and says it is not Gradient Boosting', (tester) async {
    final est = CalorieEstimate(
        status: EstimateStatus.adapted, priorTdee: 2400, tdee: 2590, observedTdee: 2870, dataShare: 0.4, reason: 'Your weight and food logs suggest your body uses about 2870 kcal a day', weighIns: 14, completeDays: 26, trendKgPerWeek: -0.07);
    await _pump(
      tester,
      CalorieTargetScreen(loader: () async => CalorieTargetData(estimate: est, weights: const [], targetKcal: 2090, formulaKcal: 1900)),
    );
    expect(find.textContaining('Personalised to you (+190 kcal a day'), findsOneWidget);
    expect(find.textContaining('The formula alone would give 1900 kcal'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('not the Gradient Boosting model'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('not the Gradient Boosting model'), findsOneWidget);
  });
}
