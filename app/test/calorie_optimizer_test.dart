import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/services/calorie_optimizer.dart';
import 'package:app/utils/health_calc.dart';

HealthProfile profile({String gender = 'Male', String dob = '1995-05-05', List<String> conditions = const [], String goal = 'Lose Weight', double weight = 80}) => HealthProfile(
      fullName: 'Test User',
      dob: dob,
      gender: gender,
      heightValue: 175,
      weightValue: weight,
      medicalConditions: conditions,
      foodAllergies: const [],
      primaryGoal: goal,
      activityLevel: 'Lightly Active',
      workoutFrequency: 3,
    );

double gauss(Random r) => sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

/// A simulated person: real maintenance [trueTdee], eats [eats] kcal a day, weighs in every other day with ±[noiseKg] scatter,
/// and logs what they eat with factor [logFactor] (1.0 = logs everything).
({List<WeightPoint> weights, List<IntakeDay> intake}) simulate({
  required DateTime today,
  required double trueTdee,
  required double eats,
  double startKg = 80,
  double noiseKg = 0.4,
  double logFactor = 1.0,
  int days = 28,
  int seed = 3,
}) {
  final r = Random(seed);
  var kg = startKg;
  final weights = <WeightPoint>[];
  final intake = <IntakeDay>[];
  for (var i = 0; i < days; i++) {
    final d = DateTime(today.year, today.month, today.day).subtract(Duration(days: days - 1 - i));
    if (i % 2 == 0) weights.add(WeightPoint(d, kg + noiseKg * gauss(r)));
    intake.add(IntakeDay(d, eats * logFactor));
    kg += (eats - trueTdee) / CalorieOptimizerRules.kcalPerKg;
  }
  return (weights: weights, intake: intake);
}

void main() {
  final today = DateTime(2026, 10, 14);
  final p = profile();
  final prior = p.tdee;
  final bmr = p.bmr;

  CalorieEstimate run(List<WeightPoint> w, List<IntakeDay> i, {double? priorTdee}) =>
      estimateMaintenance(priorTdee: priorTdee ?? prior, bmr: bmr, weights: w, intake: i, today: today);

  group('not enough data: the formula is kept and the reason is given', () {
    test('no data at all', () {
      final e = run(const [], const []);
      expect(e.status, EstimateStatus.formulaOnly);
      expect(e.tdee, prior);
      expect(e.reason, contains('at least 4 times'));
    });

    test('too few weigh-ins', () {
      final s = simulate(today: today, trueTdee: prior, eats: prior);
      final e = run(s.weights.take(3).toList(), s.intake);
      expect(e.status, EstimateStatus.formulaOnly);
      expect(e.weighIns, 3);
    });

    test('weigh-ins that cover under two weeks', () {
      final s = simulate(today: today, trueTdee: prior, eats: prior, days: 10);
      final e = run(s.weights, s.intake);
      expect(e.status, EstimateStatus.formulaOnly);
      expect(e.reason, contains('14 days'));
    });

    test('days with only a snack logged are ignored, not treated as eating little', () {
      final s = simulate(today: today, trueTdee: prior, eats: prior, logFactor: 0.12); // ~300 kcal logged a day
      final e = run(s.weights, s.intake);
      expect(e.status, EstimateStatus.formulaOnly);
      expect(e.completeDays, 0);
      expect(e.reason, contains('ignored'));
    });
  });

  group('energy balance estimate', () {
    test('a person who needs more than the formula says is moved upward, partway', () {
      final trueTdee = prior + 400;
      final s = simulate(today: today, trueTdee: trueTdee, eats: trueTdee); // weight stays flat while eating more
      final e = run(s.weights, s.intake);
      expect(e.status, EstimateStatus.adapted);
      expect(e.observedTdee!, closeTo(trueTdee, 300)); // noisy, but close
      expect(e.tdee, greaterThan(prior + 100));
      expect(e.tdee, lessThan(trueTdee)); // only part of the way
      expect(e.dataShare, lessThanOrEqualTo(CalorieOptimizerRules.maxDataShare));
    });

    test('data that agrees with the formula leaves the target unchanged', () {
      final s = simulate(today: today, trueTdee: prior, eats: prior - 500); // loses ~0.45 kg/week as expected
      final e = run(s.weights, s.intake);
      expect(e.status, EstimateStatus.confirmsFormula);
      expect(e.tdee, prior);
      expect(e.trendKgPerWeek!, lessThan(0)); // weight is falling
    });

    test('data far from the formula is not trusted (usually unlogged meals), so the formula is kept', () {
      // real intake equals real need, but only 60% of it is logged: the logs imply a need 37% below the formula
      final lowLog = simulate(today: today, trueTdee: prior, eats: prior, logFactor: 0.6);
      final e = run(lowLog.weights, lowLog.intake);
      expect(e.status, EstimateStatus.formulaOnly);
      expect(e.tdee, prior);
      expect(e.reason, contains('meals were not logged'));
      // absurdly high implied need
      final high = simulate(today: today, trueTdee: 4500, eats: 4500);
      expect(run(high.weights, high.intake).tdee, prior);
    });

    test('whatever is applied stays inside +15% / -10% of the formula', () {
      for (final f in [0.78, 0.82, 0.9, 1.0]) {
        for (final tdeeShift in [-0.2, -0.1, 0.0, 0.1, 0.25]) {
          final trueTdee = prior * (1 + tdeeShift);
          final s = simulate(today: today, trueTdee: trueTdee, eats: trueTdee, logFactor: f, noiseKg: 0.2);
          final e = run(s.weights, s.intake);
          expect(e.tdee, lessThanOrEqualTo(prior * 1.15 + 1e-9));
          expect(e.tdee, greaterThanOrEqualTo(prior * 0.90 - 1e-9));
        }
      }
    });

    test('more scatter in the weights means less trust in the data', () {
      final clean = run(simulate(today: today, trueTdee: prior + 400, eats: prior + 400, noiseKg: 0.1, seed: 5).weights,
          simulate(today: today, trueTdee: prior + 400, eats: prior + 400, noiseKg: 0.1, seed: 5).intake);
      final noisy = run(simulate(today: today, trueTdee: prior + 400, eats: prior + 400, noiseKg: 1.5, seed: 5).weights,
          simulate(today: today, trueTdee: prior + 400, eats: prior + 400, noiseKg: 1.5, seed: 5).intake);
      expect(noisy.dataShare, lessThan(clean.dataShare));
    });

    test('readings outside the 28-day window are ignored', () {
      final old = simulate(today: today.subtract(const Duration(days: 60)), trueTdee: prior + 400, eats: prior + 400);
      expect(run(old.weights, old.intake).status, EstimateStatus.formulaOnly);
    });
  });

  group('trend weight (smoothing)', () {
    test('a constant weight stays constant', () {
      final pts = [for (var i = 0; i < 6; i++) WeightPoint(DateTime(2026, 10, 1 + i), 70)];
      expect(trendWeights(pts).map((x) => x.kg), everyElement(70));
    });
    test('a step is followed gradually, and a long gap moves the trend more', () {
      final step = [WeightPoint(DateTime(2026, 10, 1), 70), WeightPoint(DateTime(2026, 10, 2), 72)];
      expect(trendWeights(step).last.kg, closeTo(70.2, 1e-9)); // alpha 0.1 after one day
      final gap = [WeightPoint(DateTime(2026, 10, 1), 70), WeightPoint(DateTime(2026, 10, 11), 72)];
      expect(trendWeights(gap).last.kg, greaterThan(70.2));
      expect(trendWeights(gap).last.kg, lessThan(72));
    });
    test('empty input', () => expect(trendWeights(const []), isEmpty));
  });

  group('safety and plan integration', () {
    final adapted = CalorieEstimate(status: EstimateStatus.adapted, priorTdee: prior, tdee: prior + 300, reason: 'x');

    test('adaptation is blocked for under-18s and for reported heart disease or diabetes', () {
      expect(CalorieOptimizerRules.adaptationBlockedReason(profile()), isNull);
      expect(CalorieOptimizerRules.adaptationBlockedReason(profile(dob: '2012-01-01')), isNotNull);
      expect(CalorieOptimizerRules.adaptationBlockedReason(profile(conditions: ['Diabetes'])), contains('diabetes'));
      expect(CalorieOptimizerRules.adaptationBlockedReason(profile(conditions: ['Heart Disease'])), isNotNull);
      for (final blocked in [profile(dob: '2012-01-01'), profile(conditions: ['Diabetes'])]) {
        final rule = HealthCalc.targetFor(blocked.primaryGoal, blocked.calorieTargets);
        expect(AdaptiveCalorieOptimizer(adapted).optimize(blocked, rule), rule); // formula target kept
      }
    });

    test('without an adaptation the rule-based target is returned unchanged', () {
      final rule = p.dailyCalorieTarget;
      expect(const AdaptiveCalorieOptimizer(null).optimize(p, rule), rule);
      final formulaOnly = CalorieEstimate(status: EstimateStatus.formulaOnly, priorTdee: prior, tdee: prior, reason: 'x');
      expect(AdaptiveCalorieOptimizer(formulaOnly).optimize(p, rule), rule);
    });

    test('an adapted estimate rebuilds the target with the same deficit rule', () {
      final rule = p.dailyCalorieTarget; // Lose Weight: tdee - 500
      final out = AdaptiveCalorieOptimizer(adapted).optimize(p, rule);
      expect(out, closeTo(rule + 300, 1));
    });

    test('the minimum safe intake still applies after adaptation', () {
      final woman = profile(gender: 'Female', weight: 55);
      final low = CalorieEstimate(status: EstimateStatus.adapted, priorTdee: woman.tdee, tdee: woman.tdee * 0.85, reason: 'x');
      final out = AdaptiveCalorieOptimizer(low).optimize(woman, woman.dailyCalorieTarget);
      expect(out, greaterThanOrEqualTo(1200));
      expect(out, greaterThanOrEqualTo(woman.bmr.round() - 1)); // never below BMR on a deficit
    });

    test('someone underweight still gets no calorie deficit', () {
      final thin = profile(weight: 50); // BMI ~16
      final est = CalorieEstimate(status: EstimateStatus.adapted, priorTdee: thin.tdee, tdee: thin.tdee * 0.9, reason: 'x');
      final out = AdaptiveCalorieOptimizer(est).optimize(thin, thin.dailyCalorieTarget);
      expect(out, est.tdee.round()); // maintenance, not maintenance - 500
    });

    test('disabled estimate says why and changes nothing', () {
      final e = CalorieEstimate.disabled(prior, 'reason');
      expect(e.status, EstimateStatus.disabled);
      expect(e.tdee, prior);
      expect(e.adjustment, 0);
    });
  });
}
