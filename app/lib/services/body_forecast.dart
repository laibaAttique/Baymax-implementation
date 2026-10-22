import 'dart:math' as math;

/// Module 11 (Predictive Body Transformation): where a person's weight and body fat go over 30 days, and how long a target takes, for a
/// chosen daily calorie change and number of workouts a week.
///
/// **This is an energy-balance model, not a trained model.** It needs no data from other people, and none of the datasets available to the
/// project contains weight-change trajectories to train on (the project scope names Gradient Boosting Regression for this; that stays
/// unbuilt until such data exists, see PROGRESS.md). What it does, one day at a time:
///
///  1. Intake is fixed at maintenance minus the chosen deficit, but never below the safe floor (the larger of the BMR and 1,500 kcal for
///     men or 1,200 kcal for women, the same floor as the calorie target). A deficit is not applied to an underweight person.
///  2. Energy expenditure follows body weight: it falls by 100 kJ (23.9 kcal) a day for every kg lost, which is what makes loss slow
///     down (Hall KD et al. Lancet 2011;378:826-837, the slope of its dynamic model; its regression on doubly labelled water data gave
///     94 kJ/kg/day).
///  3. The imbalance changes body mass at the energy density of what is gained or lost: 39.5 MJ per kg of fat and 7.6 MJ per kg of lean
///     mass (same paper).
///  4. How much of a weight change is lean mass comes from Forbes's relation, lean share = 10.4 / (10.4 + fat mass in kg) (Hall KD, Br J
///     Nutr 2007;97:1059-1063): the fatter a person is, the more of a loss is fat.
///  5. Starting fat mass is estimated from BMI, age and sex (Deurenberg P, Weststrate JA, Seidell JC, Br J Nutr 1991;65:105-114: body fat % =
///     1.20 x BMI + 0.23 x age - 10.8 x sex (1 for men, 0 for women) - 5.4; standard error 4.1 percentage points, slightly too high in
///     people with obesity).
///
/// Not modelled: water and glycogen (the first week usually shows a bigger drop than fat alone), menstrual cycle, medicines, and
/// whether the person really eats what they plan. The figures are estimates for planning, not a promise and not medical advice.
class ForecastInputs {
  final double weightKg;
  final double heightCm;
  final int age;
  final bool isMale;

  /// Maintenance energy (BMR x activity factor) and BMR, as the rest of the app works them out.
  final double tdee;
  final double bmr;

  /// Planned daily calorie deficit from food; negative for a surplus (gaining).
  final double deficitKcal;
  final int workoutsPerWeek;

  /// The workouts a week already part of the person's maintenance energy (their profile's workout frequency).
  final int usualWorkoutsPerWeek;
  final double? targetKg;

  const ForecastInputs({
    required this.weightKg,
    required this.heightCm,
    required this.age,
    required this.isMale,
    required this.tdee,
    required this.bmr,
    required this.deficitKcal,
    required this.workoutsPerWeek,
    this.usualWorkoutsPerWeek = 0,
    this.targetKg,
  });

  double get bmi => weightKg / math.pow(heightCm / 100, 2);

  ForecastInputs copyWith({double? weightKg, double? deficitKcal, int? workoutsPerWeek, double? targetKg, bool clearTarget = false}) => ForecastInputs(
        weightKg: weightKg ?? this.weightKg,
        heightCm: heightCm,
        age: age,
        isMale: isMale,
        tdee: tdee,
        bmr: bmr,
        deficitKcal: deficitKcal ?? this.deficitKcal,
        workoutsPerWeek: workoutsPerWeek ?? this.workoutsPerWeek,
        usualWorkoutsPerWeek: usualWorkoutsPerWeek,
        targetKg: clearTarget ? null : (targetKg ?? this.targetKg),
      );
}

class ForecastPoint {
  final int day;
  final double kg;
  final double fatKg;
  const ForecastPoint(this.day, this.kg, this.fatKg);
}

class ForecastMilestone {
  final String label;
  final int day;
  final double kg;
  const ForecastMilestone(this.label, this.day, this.kg);
}

class BodyForecast {
  final ForecastInputs inputs;

  /// Day 0 to 30, following the plan fully.
  final List<ForecastPoint> days;

  /// The same 30 days if only 60% of the planned change is achieved (a more cautious picture, not a statistical range).
  final List<ForecastPoint> cautious;
  final double bodyFatPct0;
  final double bodyFatPct30;
  final double weightIn30;
  final double fatChange30; // kg, negative = fat lost
  final double leanChange30;
  final double intakeKcal;
  final double effectiveDeficit;

  /// Days until the target weight is reached, or null (no target, already there, or never reached).
  final int? daysToTarget;
  final bool targetMovesAway;
  final bool targetUnreachable;

  /// Where weight stands after two years of keeping the plan. It is heading for the level where energy expenditure (which falls as weight
  /// falls) meets intake, and is about 95% of the way there by then.
  final double plateauKg;
  final List<ForecastMilestone> milestones;
  final List<String> notes;

  const BodyForecast({
    required this.inputs,
    required this.days,
    required this.cautious,
    required this.bodyFatPct0,
    required this.bodyFatPct30,
    required this.weightIn30,
    required this.fatChange30,
    required this.leanChange30,
    required this.intakeKcal,
    required this.effectiveDeficit,
    required this.daysToTarget,
    required this.targetMovesAway,
    required this.targetUnreachable,
    required this.plateauKg,
    required this.milestones,
    required this.notes,
  });

  double get changeIn30 => weightIn30 - inputs.weightKg;
}

class BodyForecaster {
  BodyForecaster._();

  /// Fall in energy expenditure per kg of weight lost, kcal a day (100 kJ / 4.184).
  static const adaptKcalPerKg = 100 / 4.184;
  static const fatKcalPerKg = 39500 / 4.184; // 9,441
  static const leanKcalPerKg = 7600 / 4.184; // 1,816
  static const forbesC = 10.4;

  /// Net energy of one moderate workout, kcal per kg of body weight: about 5 METs for 45 minutes minus the 1 MET of resting = 4 x 0.75.
  /// An estimate (the 2024 Compendium of Physical Activities gives 3.5 to 6 METs for general strength and mixed training).
  static const sessionKcalPerKg = 3.0;

  static const maxDeficit = 1000.0;
  static const maxSurplus = 500.0;
  static const horizonDays = 730;

  static double bodyFatPercent({required double bmi, required int age, required bool isMale}) =>
      (1.20 * bmi + 0.23 * age - 10.8 * (isMale ? 1 : 0) - 5.4).clamp(5.0, 60.0);

  static double intakeFloor(ForecastInputs i) => math.max(i.bmr, i.isMale ? 1500.0 : 1200.0);

  static BodyForecast forecast(ForecastInputs raw) {
    final notes = <String>[];
    var deficit = raw.deficitKcal.clamp(-maxSurplus, maxDeficit);
    if (deficit != raw.deficitKcal) notes.add('The calorie change was limited to ${deficit > 0 ? '$maxDeficit kcal a day less' : '$maxSurplus kcal a day more'} than maintenance.');
    final floor = intakeFloor(raw);

    if (raw.bmi > 0 && raw.bmi < 18.5 && deficit > 0) {
      deficit = 0;
      notes.add('A calorie deficit is not applied because your BMI is in the underweight range. The forecast shows maintenance.');
    }
    var intake = raw.tdee - deficit;
    if (deficit > 0 && intake < floor) {
      intake = floor;
      notes.add('Your intake was kept at ${floor.round()} kcal a day, the minimum safe amount for you, so the deficit is smaller than the one you entered.');
    }
    final effectiveDeficit = raw.tdee - intake;

    final bf0 = bodyFatPercent(bmi: raw.bmi, age: raw.age, isMale: raw.isMale);
    final extraPerDay = (raw.workoutsPerWeek - raw.usualWorkoutsPerWeek) * sessionKcalPerKg * raw.weightKg / 7;

    List<ForecastPoint> simulate(double share, {int days = horizonDays}) {
      var w = raw.weightKg;
      var fm = math.max(3.0, bf0 / 100 * raw.weightKg);
      final out = <ForecastPoint>[ForecastPoint(0, w, fm)];
      final dayIntake = raw.tdee - effectiveDeficit * share;
      final dayExtra = extraPerDay * share;
      for (var d = 1; d <= days; d++) {
        final expenditure = raw.tdee + adaptKcalPerKg * (w - raw.weightKg) + dayExtra;
        final balance = dayIntake - expenditure;
        final lean = forbesC / (forbesC + fm);
        final density = lean * leanKcalPerKg + (1 - lean) * fatKcalPerKg;
        final dw = balance / density;
        w += dw;
        fm = math.max(1.0, fm + (1 - lean) * dw);
        out.add(ForecastPoint(d, w, fm));
      }
      return out;
    }

    final full = simulate(1.0);
    final slow = simulate(0.6, days: 30);
    final p30 = full[30];
    final fm0 = full.first.fatKg;
    final change = p30.kg - raw.weightKg;
    final fatChange = p30.fatKg - fm0;

    // ---- target and timeline -------------------------------------------------------------------------------------------------
    int? daysToTarget;
    var movesAway = false;
    var unreachable = false;
    final target = raw.targetKg;
    final plateau = full.last.kg;
    final milestones = <ForecastMilestone>[];
    if (target != null && (target - raw.weightKg).abs() >= 0.1) {
      final wantDown = target < raw.weightKg;
      final trend = full[30].kg - raw.weightKg;
      if (trend.abs() < 0.05 || (wantDown && trend > 0) || (!wantDown && trend < 0)) {
        movesAway = trend.abs() >= 0.05;
        unreachable = true;
      } else {
        for (final p in full) {
          if (wantDown ? p.kg <= target : p.kg >= target) {
            daysToTarget = p.day;
            break;
          }
        }
        unreachable = daysToTarget == null;
        for (final frac in const [0.25, 0.5, 0.75, 1.0]) {
          final goal = raw.weightKg + (target - raw.weightKg) * frac;
          final hit = full.where((p) => wantDown ? p.kg <= goal : p.kg >= goal).firstOrNull;
          if (hit != null) milestones.add(ForecastMilestone(frac == 1.0 ? 'Target reached' : '${(frac * 100).round()}% of the way', hit.day, goal));
        }
      }
    } else if (change.abs() >= 0.05 || effectiveDeficit.abs() >= 1) {
      final down = effectiveDeficit >= 0;
      for (final step in const [1.0, 2.0, 5.0]) {
        final goal = raw.weightKg + (down ? -step : step);
        final hit = full.where((p) => down ? p.kg <= goal : p.kg >= goal).firstOrNull;
        if (hit != null && hit.day > 0) milestones.add(ForecastMilestone('${down ? 'Down' : 'Up'} ${step.toStringAsFixed(0)} kg', hit.day, goal));
      }
    }

    if (extraPerDay.abs() >= 1) {
      notes.add('${raw.workoutsPerWeek} workouts a week, compared with the ${raw.usualWorkoutsPerWeek} already in your maintenance calories, ${extraPerDay > 0 ? 'adds' : 'removes'} about ${extraPerDay.abs().round()} kcal a day.');
    }
    if (unreachable && target != null && !movesAway && daysToTarget == null && (target - raw.weightKg).abs() >= 0.1 && effectiveDeficit.abs() >= 1) {
      notes.add('At this plan your weight levels off near ${plateau.toStringAsFixed(1)} kg, because your body needs fewer calories as it gets lighter. A bigger change, or more activity, is needed to reach ${target.toStringAsFixed(1)} kg.');
    }

    return BodyForecast(
      inputs: raw.copyWith(deficitKcal: deficit),
      days: full.take(31).toList(),
      cautious: slow,
      bodyFatPct0: fm0 / raw.weightKg * 100,
      bodyFatPct30: p30.fatKg / p30.kg * 100,
      weightIn30: p30.kg,
      fatChange30: fatChange,
      leanChange30: change - fatChange,
      intakeKcal: intake,
      effectiveDeficit: effectiveDeficit,
      daysToTarget: daysToTarget,
      targetMovesAway: movesAway,
      targetUnreachable: unreachable,
      plateauKg: plateau,
      milestones: milestones,
      notes: notes,
    );
  }

  /// "lose 7 kg" or "gain 3.5 kg" typed by the person: the target weight it means, or null when the text holds no such goal.
  static double? targetFromGoalText(String text, double currentKg) {
    final m = RegExp(r'(lose|loss|drop|gain|add|build)\D{0,12}(\d{1,3}(?:\.\d{1,2})?)\s*(kg|kgs|kilo|kilos|lb|lbs|pounds?)', caseSensitive: false).firstMatch(text);
    if (m == null) return null;
    var amount = double.parse(m.group(2)!);
    if (m.group(3)!.toLowerCase().startsWith('lb') || m.group(3)!.toLowerCase().startsWith('pound')) amount *= 0.45359237;
    if (amount <= 0 || amount > 100) return null;
    final gain = const ['gain', 'add', 'build'].contains(m.group(1)!.toLowerCase());
    final t = currentKg + (gain ? amount : -amount);
    return t < 25 ? null : t;
  }
}
