import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/screens/analytics/body_transform_screen.dart';
import 'package:app/screens/analytics/transform_forecast_screens.dart';
import 'package:app/services/body_forecast.dart';
import 'package:app/services/calorie_optimizer.dart';
import 'package:app/services/weight_projection.dart';
import 'package:app/theme/app_theme.dart';

ForecastInputs _in({double weight = 80, double height = 175, int age = 30, bool male = true, double tdee = 2600, double bmr = 1800, double deficit = 500, int workouts = 3, int usual = 3, double? target}) =>
    ForecastInputs(weightKg: weight, heightCm: height, age: age, isMale: male, tdee: tdee, bmr: bmr, deficitKcal: deficit, workoutsPerWeek: workouts, usualWorkoutsPerWeek: usual, targetKg: target);

BodyForecast _f(ForecastInputs i) => BodyForecaster.forecast(i);

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(1170, 4200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: w));
  await tester.pumpAndSettle();
}

void main() {
  group('the energy-balance model keeps to physiology', () {
    test('no change in food or exercise means no change in weight', () {
      final f = _f(_in(deficit: 0));
      expect((f.weightIn30 - 80).abs(), lessThan(0.05));
      expect(f.fatChange30.abs(), lessThan(0.05));
    });

    test('a 500 kcal deficit loses a believable 1.5 to 3 kg in a month, mostly fat', () {
      final f = _f(_in());
      expect(f.changeIn30, inInclusiveRange(-3.0, -1.5));
      expect(f.fatChange30, lessThan(f.leanChange30 * 0 - 0.8));
      expect(f.fatChange30.abs(), greaterThan(f.leanChange30.abs())); // more fat than lean lost
      expect(f.bodyFatPct30, lessThan(f.bodyFatPct0));
    });

    test('a bigger deficit loses more, and so does more exercise', () {
      final a = _f(_in(deficit: 250)).weightIn30;
      final b = _f(_in(deficit: 500)).weightIn30;
      final c = _f(_in(deficit: 750)).weightIn30;
      expect(a, greaterThan(b));
      expect(b, greaterThan(c));
      expect(_f(_in(workouts: 5)).weightIn30, lessThan(_f(_in(workouts: 3)).weightIn30));
      expect(_f(_in(workouts: 2)).weightIn30, greaterThan(_f(_in(workouts: 3)).weightIn30)); // fewer than usual
    });

    test('loss slows down as the body gets lighter', () {
      final f = _f(_in(deficit: 700));
      final firstWeek = f.days[0].kg - f.days[7].kg;
      final lastWeek = f.days[23].kg - f.days[30].kg;
      expect(lastWeek, lessThan(firstWeek));
    });

    test('weight heads for where expenditure meets intake, deficit / 23.9 kg below the start, and is most of the way there after two years', () {
      final f = _f(_in(deficit: 500, workouts: 3));
      final limit = 80 - 500 / BodyForecaster.adaptKcalPerKg;
      expect(f.plateauKg, greaterThan(limit)); // it approaches the limit and never crosses it
      expect(f.plateauKg, closeTo(limit, 1.0));
    });

    test('eating more gains weight, and a fatter person loses a larger share as fat', () {
      final gain = _f(_in(deficit: -300));
      expect(gain.changeIn30, greaterThan(0.5));
      expect(gain.fatChange30, greaterThan(0));
      final lean = _f(_in(weight: 60, height: 180, deficit: 500, tdee: 2300, bmr: 1600));
      final heavy = _f(_in(weight: 120, height: 175, deficit: 500, tdee: 3100, bmr: 2200));
      expect(heavy.fatChange30.abs() / heavy.changeIn30.abs(), greaterThan(lean.fatChange30.abs() / lean.changeIn30.abs()));
    });

    test('the cautious path (60% followed) loses less than the planned path', () {
      final f = _f(_in());
      expect(f.cautious.last.kg, greaterThan(f.days.last.kg));
      expect(f.cautious.last.kg, lessThan(80));
    });

    test('intake never goes below the safe floor, and the person is told', () {
      final f = _f(_in(deficit: 1000)); // 2600 - 1000 = 1600, floor is max(BMR 1800, 1500) = 1800
      expect(f.intakeKcal, 1800);
      expect(f.effectiveDeficit, 800);
      expect(f.notes.any((n) => n.contains('minimum safe amount')), isTrue);
      final woman = _f(_in(male: false, tdee: 1700, bmr: 1300, deficit: 800));
      expect(woman.intakeKcal, greaterThanOrEqualTo(1300));
    });

    test('an underweight person gets maintenance, not a deficit', () {
      final f = _f(_in(weight: 45, height: 170, deficit: 500, tdee: 1900, bmr: 1300));
      expect(f.effectiveDeficit, 0);
      expect(f.notes.any((n) => n.contains('underweight')), isTrue);
    });

    test('entries outside the allowed range are limited', () {
      expect(_f(_in(deficit: 3000)).inputs.deficitKcal, lessThanOrEqualTo(1000));
      expect(_f(_in(deficit: -2000)).inputs.deficitKcal, greaterThanOrEqualTo(-500));
    });
  });

  group('the target and the milestones', () {
    test('a reachable target gets a date and milestones in order', () {
      final f = _f(_in(deficit: 500, target: 72));
      expect(f.daysToTarget, isNotNull);
      expect(f.targetUnreachable, isFalse);
      final days = f.milestones.map((m) => m.day).toList();
      expect(days, orderedEquals([...days]..sort()));
      expect(f.milestones.last.label, 'Target reached');
      expect(f.milestones.first.label, '25% of the way');
    });

    test('a target below where the plan levels off is never reached, and the person is told where it levels off', () {
      final f = _f(_in(deficit: 250, target: 60));
      expect(f.daysToTarget, isNull);
      expect(f.targetUnreachable, isTrue);
      expect(f.notes.any((n) => n.contains('levels off')), isTrue);
    });

    test('a target in the other direction is flagged', () {
      final f = _f(_in(deficit: 500, target: 90));
      expect(f.targetMovesAway, isTrue);
      expect(f.daysToTarget, isNull);
    });

    test('with no target the milestones are 1, 2 and 5 kg', () {
      final f = _f(_in(deficit: 700));
      expect(f.milestones.map((m) => m.label), ['Down 1 kg', 'Down 2 kg', 'Down 5 kg']);
    });

    test('goal text such as "Lose 7 kg" is understood, other text is not', () {
      expect(BodyForecaster.targetFromGoalText('Lose 7 kg', 80), 73);
      expect(BodyForecaster.targetFromGoalText('I want to gain 3.5 kg of muscle', 70), 73.5);
      expect(BodyForecaster.targetFromGoalText('lose 15 lbs', 80)!, closeTo(80 - 6.80, 0.01));
      expect(BodyForecaster.targetFromGoalText('get fit', 80), isNull);
      expect(BodyForecaster.targetFromGoalText('lose 500 kg', 80), isNull);
      expect(BodyForecaster.targetFromGoalText('', 80), isNull);
    });

    test('the same inputs always give the same forecast', () {
      expect(_f(_in(target: 72)).weightIn30, _f(_in(target: 72)).weightIn30);
    });
  });

  group('the screens', () {
    final profile = HealthProfile(
      fullName: 'T', dob: '${DateTime.now().year - 30}-01-01', gender: 'Male', heightValue: 175, weightValue: 80, primaryGoal: 'Lose Weight', activityLevel: 'Moderately Active',
      workoutFrequency: 3, targetWeightValue: 72,
    );

    testWidgets('inputs are checked, then the forecast shows the 30-day result, a goal and the method', (tester) async {
      await _pump(tester, TransformInputScreen(seed: ForecastSeed.fromProfile(profile)));
      expect(find.text('Predict My Results'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '1500');
      await tester.tap(find.text('Predict My Results'));
      await tester.pumpAndSettle();
      expect(find.textContaining('from 0 to 1000'), findsOneWidget);
      expect(find.text('Your forecast'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '500');
      await tester.enterText(find.byType(TextField).last, 'Lose 7 kg');
      await tester.tap(find.text('Predict My Results'));
      await tester.pumpAndSettle();
      expect(find.text('Your forecast'), findsOneWidget);
      expect(find.text('Weight in 30 days'), findsOneWidget);
      expect(find.text('Body fat'), findsOneWidget);
      expect(find.textContaining('Goal 73.0 kg'), findsOneWidget);
      expect(find.textContaining('Method: an energy-balance model, not a trained'), findsOneWidget);
      expect(find.text('Milestones'), findsOneWidget);
    });

    testWidgets('changing the inputs changes the forecast', (tester) async {
      await _pump(tester, TransformResultScreen(inputs: _in(deficit: 500)));
      final before = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().firstWhere((t) => RegExp(r'^\d+\.\d kg$').hasMatch(t) && t != '80.0 kg');
      await tester.tap(find.text('Adjust inputs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5').last);
      await tester.pumpAndSettle();
      final after = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().firstWhere((t) => RegExp(r'^\d+\.\d kg$').hasMatch(t) && t != '80.0 kg');
      expect(after, isNot(before));
    });

    testWidgets('the forecast can be copied to share', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(tester, TransformResultScreen(inputs: _in(target: 72)));
      await tester.tap(find.text('Copy My Forecast'));
      await tester.pumpAndSettle();
      expect(copied, contains('30-day forecast'));
      expect(copied, contains('not medical advice'));
      expect(find.textContaining('Forecast copied'), findsOneWidget);
    });

    testWidgets('a safety limit is explained on the result screen', (tester) async {
      await _pump(tester, TransformResultScreen(inputs: _in(deficit: 1000)));
      expect(find.textContaining('minimum safe amount'), findsOneWidget);
    });

    testWidgets('the hub offers the forecast, keeps the weigh-in trend and says the trend is not a model', (tester) async {
      final weights = [for (var i = 0; i < 8; i++) WeightPoint(DateTime(2026, 10, 14).subtract(Duration(days: 26 - i * 3)), 60 - i * 0.2)];
      await _pump(
        tester,
        BodyTransformScreen(loader: () async => BodyTransformData(projectWeight(weights: weights, today: DateTime(2026, 10, 14), targetKg: 57), weights, 57, 60, seed: ForecastSeed.fromProfile(profile))),
      );
      expect(find.text('Predict my results'), findsWidgets);
      expect(find.textContaining('Trend weight now'), findsOneWidget);
      await tester.tap(find.text('Predict my results').last);
      await tester.pumpAndSettle();
      expect(find.text('Daily calorie change'), findsOneWidget);
    });
  });
}
