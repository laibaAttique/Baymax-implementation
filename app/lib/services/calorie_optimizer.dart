import 'dart:math';
import '../models/health_profile.dart';
import '../utils/health_calc.dart';
import 'plan_generator.dart';

/// Module 3, FR-4: personalises the daily calorie target from the user's own weight and food logs.
///
/// This is an adaptive estimator based on energy balance, not a trained model. The scope names Gradient Boosting for this
/// requirement; that needs measured daily-energy data the team does not have, so this algorithm is used instead.
///
/// Idea: if someone eats `I` kcal a day on average and their weight changes by `s` kg a day, their real maintenance
/// energy is about `I - s * 7700`. That observation is noisy (water weight, logging errors), so it is combined with the
/// formula-based estimate (Mifflin-St Jeor x activity factor) in proportion to how reliable each is (a normal-normal
/// Bayesian update), and the result is kept within safety limits.

class WeightPoint {
  final DateTime date;
  final double kg;
  const WeightPoint(this.date, this.kg);
}

class IntakeDay {
  final DateTime date;
  final double kcal;
  const IntakeDay(this.date, this.kcal);
}

enum EstimateStatus {
  /// Not enough (or not usable) data yet: the formula is used.
  formulaOnly,

  /// The data agrees with the formula within normal noise: the formula is used.
  confirmsFormula,

  /// The data moved the estimate away from the formula.
  adapted,

  /// Adaptation is switched off for this user for safety (see [CalorieOptimizerRules.adaptationBlockedReason]).
  disabled,
}

class CalorieEstimate {
  final EstimateStatus status;

  /// Maintenance calories from the formula, and the value the target is built on (equal unless [adapted]).
  final double priorTdee;
  final double tdee;

  /// What the logs implied on their own, and how much weight that got (0..[CalorieOptimizerRules.maxDataShare]).
  final double? observedTdee;
  final double dataShare;

  /// Plain-language explanation shown to the user.
  final String reason;

  final int weighIns;
  final int completeDays;
  final double? trendKgPerWeek;

  const CalorieEstimate({
    required this.status,
    required this.priorTdee,
    required this.tdee,
    required this.reason,
    this.observedTdee,
    this.dataShare = 0,
    this.weighIns = 0,
    this.completeDays = 0,
    this.trendKgPerWeek,
  });

  /// Adaptation is off for this user; the formula is used and [reason] says why.
  factory CalorieEstimate.disabled(double priorTdee, String reason) =>
      CalorieEstimate(status: EstimateStatus.disabled, priorTdee: priorTdee, tdee: priorTdee, reason: reason);

  double get adjustment => tdee - priorTdee;
  bool get adapted => status == EstimateStatus.adapted;
}

class CalorieOptimizerRules {
  CalorieOptimizerRules._();

  /// Approximate energy in 1 kg of body weight change (about 3,500 kcal per pound). A rule of thumb: the real value varies
  /// with what is gained or lost and changes over time.
  static const kcalPerKg = 7700.0;

  static const windowDays = 28;
  static const minWeighIns = 4;
  static const minSpanDays = 14;
  static const minCompleteDays = 10;

  /// A logged day counts only if it holds at least this share of the user's BMR (a day with one snack logged is not a day of eating).
  static const completeDayShareOfBmr = 0.6;

  /// Assumed uncertainty of the formula for one person, and of calorie logging (both fractions; team assumptions, not measured).
  static const formulaUncertainty = 0.10;
  static const loggingUncertainty = 0.10;

  /// Safety limits: the data may raise the estimate by at most [maxIncrease] and lower it by at most [maxDecrease] (fractions of
  /// the formula value; lowering a calorie target is the riskier direction, so it is limited more), and never counts for more than
  /// [maxDataShare] of the result.
  static const maxIncrease = 0.15;
  static const maxDecrease = 0.10;
  static const maxDataShare = 0.7;

  /// If the logs imply a need further than this from the formula, the data is not trusted at all: real differences between
  /// people are smaller, and a gap this large is almost always unlogged meals or a logging mistake. Team choice (conservative).
  static const plausibleBand = 0.30;

  /// Changes smaller than this are noise and are not applied (also prevents the target from jittering).
  static const minApplied = 100.0;

  /// Why adaptation must stay off for this person, or null when it is allowed.
  static String? adaptationBlockedReason(HealthProfile p) {
    final age = p.age;
    if (age == null || age < 18) return 'Automatic adjustment is only for adults, because growth changes weight.';
    if (p.hasCondition('Heart Disease') || p.hasCondition('Diabetes')) {
      return 'Because you reported a heart condition or diabetes, your calorie target stays with the cautious formula. Ask your doctor or dietitian before changing it.';
    }
    return null;
  }
}

/// Least-squares line through (day, kg): slope per day, its standard error, and the line's value at the last weigh-in.
class WeightFit {
  final double slopePerDay;
  final double seSlope;
  final double lastFitKg;
  const WeightFit(this.slopePerDay, this.seSlope, this.lastFitKg);
}

WeightFit? fitWeights(List<WeightPoint> pts) {
  final n = pts.length;
  if (n < 3) return null;
  final t0 = pts.first.date;
  final xs = [for (final p in pts) p.date.difference(t0).inHours / 24.0];
  final ys = [for (final p in pts) p.kg];
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  var sxx = 0.0, sxy = 0.0;
  for (var i = 0; i < n; i++) {
    sxx += (xs[i] - mx) * (xs[i] - mx);
    sxy += (xs[i] - mx) * (ys[i] - my);
  }
  if (sxx == 0) return null;
  final slope = sxy / sxx;
  final intercept = my - slope * mx;
  var sse = 0.0;
  for (var i = 0; i < n; i++) {
    final r = ys[i] - (intercept + slope * xs[i]);
    sse += r * r;
  }
  final sigma2 = sse / (n - 2);
  return WeightFit(slope, sqrt(sigma2 / sxx), intercept + slope * xs.last);
}

/// Exponentially smoothed ("trend") weight for display, handling gaps between weigh-ins: a weigh-in after a long gap moves the
/// trend more than one the next day. [alpha] is the weight of a new reading after one day.
List<WeightPoint> trendWeights(List<WeightPoint> weights, {double alpha = 0.1}) {
  if (weights.isEmpty) return const [];
  final sorted = [...weights]..sort((a, b) => a.date.compareTo(b.date));
  final out = <WeightPoint>[WeightPoint(sorted.first.date, sorted.first.kg)];
  for (var i = 1; i < sorted.length; i++) {
    final gap = max(1, sorted[i].date.difference(sorted[i - 1].date).inDays);
    final a = 1 - pow(1 - alpha, gap).toDouble();
    out.add(WeightPoint(sorted[i].date, out.last.kg + a * (sorted[i].kg - out.last.kg)));
  }
  return out;
}

/// Estimates the user's maintenance calories (TDEE) from [weights] and [intake] over the last [CalorieOptimizerRules.windowDays] days.
CalorieEstimate estimateMaintenance({
  required double priorTdee,
  required double bmr,
  required List<WeightPoint> weights,
  required List<IntakeDay> intake,
  required DateTime today,
}) {
  CalorieEstimate formula(String why, {int weighIns = 0, int complete = 0}) => CalorieEstimate(
      status: EstimateStatus.formulaOnly, priorTdee: priorTdee, tdee: priorTdee, reason: why, weighIns: weighIns, completeDays: complete);

  final t = DateTime(today.year, today.month, today.day);
  final from = t.subtract(const Duration(days: CalorieOptimizerRules.windowDays - 1));
  final w = [for (final p in weights) if (!p.date.isBefore(from) && !p.date.isAfter(t)) p]..sort((a, b) => a.date.compareTo(b.date));
  if (w.length < CalorieOptimizerRules.minWeighIns) {
    return formula('Log your weight at least ${CalorieOptimizerRules.minWeighIns} times over ${CalorieOptimizerRules.minSpanDays}+ days to personalise your target (so far ${w.length}).',
        weighIns: w.length);
  }
  final span = w.last.date.difference(w.first.date).inDays;
  if (span < CalorieOptimizerRules.minSpanDays) {
    return formula('Your weigh-ins cover $span days; ${CalorieOptimizerRules.minSpanDays} days are needed so that real change can be told apart from daily ups and downs.', weighIns: w.length);
  }
  final minDay = CalorieOptimizerRules.completeDayShareOfBmr * bmr;
  final complete = [for (final d in intake) if (!d.date.isBefore(w.first.date) && !d.date.isAfter(w.last.date) && d.kcal >= minDay) d];
  if (complete.length < CalorieOptimizerRules.minCompleteDays) {
    return formula(
        'Log everything you eat on at least ${CalorieOptimizerRules.minCompleteDays} of those days (so far ${complete.length}). Days with only a few foods logged are ignored, because they would make your needs look lower than they are.',
        weighIns: w.length,
        complete: complete.length);
  }
  final fit = fitWeights(w);
  if (fit == null) return formula('Not enough variation in the weigh-in dates yet.', weighIns: w.length, complete: complete.length);

  final meanIntake = complete.fold(0.0, (s, d) => s + d.kcal) / complete.length;
  final observed = meanIntake - fit.slopePerDay * CalorieOptimizerRules.kcalPerKg;
  if ((observed / priorTdee - 1).abs() > CalorieOptimizerRules.plausibleBand) {
    return CalorieEstimate(
      status: EstimateStatus.formulaOnly,
      priorTdee: priorTdee,
      tdee: priorTdee,
      observedTdee: observed,
      reason: 'Your logs imply about ${observed.round()} kcal a day, far from the formula\'s ${priorTdee.round()}. That usually means some meals were not logged, so the formula is kept. '
          'Log everything you eat and weigh yourself at similar times for two weeks, then check again.',
      weighIns: w.length,
      completeDays: complete.length,
      trendKgPerWeek: fit.slopePerDay * 7,
    );
  }

  // Normal-normal update: prior = formula, observation = energy balance. Variances in kcal^2.
  final sigmaPrior = CalorieOptimizerRules.formulaUncertainty * priorTdee;
  final seBalance = fit.seSlope * CalorieOptimizerRules.kcalPerKg;
  final sigmaObs = sqrt(seBalance * seBalance + pow(CalorieOptimizerRules.loggingUncertainty * meanIntake, 2));
  final share = min(CalorieOptimizerRules.maxDataShare, sigmaPrior * sigmaPrior / (sigmaPrior * sigmaPrior + sigmaObs * sigmaObs));
  var tdee = priorTdee + share * (observed - priorTdee);
  tdee = tdee.clamp(priorTdee * (1 - CalorieOptimizerRules.maxDecrease), priorTdee * (1 + CalorieOptimizerRules.maxIncrease)).toDouble();

  final trendPerWeek = fit.slopePerDay * 7;
  if ((tdee - priorTdee).abs() < CalorieOptimizerRules.minApplied) {
    return CalorieEstimate(
      status: EstimateStatus.confirmsFormula,
      priorTdee: priorTdee,
      tdee: priorTdee,
      observedTdee: observed,
      dataShare: share,
      reason: 'Your logs are consistent with the formula (they suggest about ${observed.round()} kcal a day against ${priorTdee.round()}), so your target is unchanged.',
      weighIns: w.length,
      completeDays: complete.length,
      trendKgPerWeek: trendPerWeek,
    );
  }
  final dir = tdee > priorTdee ? 'more' : 'fewer';
  return CalorieEstimate(
    status: EstimateStatus.adapted,
    priorTdee: priorTdee,
    tdee: tdee,
    observedTdee: observed,
    dataShare: share,
    reason: 'Your weight and food logs suggest your body uses about ${observed.round()} kcal a day, $dir than the formula\'s ${priorTdee.round()}. '
        'The estimate is moved ${((tdee - priorTdee).abs()).round()} kcal toward that, no more than ${(CalorieOptimizerRules.maxDataShare * 100).round()}% of the way, never more than ${(CalorieOptimizerRules.maxIncrease * 100).round()}% above or ${(CalorieOptimizerRules.maxDecrease * 100).round()}% below the formula.',
    weighIns: w.length,
    completeDays: complete.length,
    trendKgPerWeek: trendPerWeek,
  );
}

/// Plugs the estimate into the plan generator (the `CalorieOptimizer` seam, FR-4). The target is rebuilt from the adjusted
/// maintenance calories with the same safety floors and underweight rule as the formula-based target.
class AdaptiveCalorieOptimizer implements CalorieOptimizer {
  final CalorieEstimate? estimate;
  const AdaptiveCalorieOptimizer(this.estimate);

  @override
  int optimize(HealthProfile profile, int ruleBasedKcal) {
    final e = estimate;
    if (e == null || !e.adapted || CalorieOptimizerRules.adaptationBlockedReason(profile) != null) return ruleBasedKcal;
    final targets = HealthCalc.calorieTargets(bmr: profile.bmr, tdee: e.tdee, gender: profile.gender, bmi: profile.bmi);
    return HealthCalc.targetFor(profile.primaryGoal, targets);
  }
}
