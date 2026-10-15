/// Pure health maths for Module 1 (FE-6/7/8) and the plan generator (Module 3).
class CalorieTargets {
  final int maintain;
  final int deficit;
  final int surplus;

  /// Set when the deficit was limited for safety (shown to the user).
  final String? safetyNote;

  const CalorieTargets({
    required this.maintain,
    required this.deficit,
    required this.surplus,
    this.safetyNote,
  });
}

class Macros {
  final int proteinG;
  final int carbsG;
  final int fatG;
  const Macros({required this.proteinG, required this.carbsG, required this.fatG});
}

class HealthCalc {
  HealthCalc._();

  // --- Units -------------------------------------------------------------

  /// Height in feet is entered as decimal feet (e.g. 5.5).
  static double toCm(double value, String unit) => unit == 'ft' ? value * 30.48 : value;

  static double toKg(double value, String unit) => unit == 'lbs' ? value * 0.45359237 : value;

  /// The reverse conversions, used when the user switches a unit and the number in the field must follow.
  static double fromCm(double cm, String unit) => unit == 'ft' ? cm / 30.48 : cm;

  static double fromKg(double kg, String unit) => unit == 'lbs' ? kg / 0.45359237 : kg;

  // --- BMI (WHO) ---------------------------------------------------------

  static double bmi(double weightKg, double heightCm) {
    if (weightKg <= 0 || heightCm <= 0) return 0;
    final m = heightCm / 100;
    return weightKg / (m * m);
  }

  /// WHO adult BMI categories.
  static String whoCategory(double bmi) {
    if (bmi <= 0) return 'Unknown';
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Normal';
    if (bmi < 30) return 'Overweight';
    if (bmi < 35) return 'Obese (Class I)';
    if (bmi < 40) return 'Obese (Class II)';
    return 'Obese (Class III)';
  }

  // --- Age ---------------------------------------------------------------

  /// [dob] is an ISO date (`YYYY-MM-DD`). Returns null when missing/invalid.
  static int? ageFromDob(String dob, {DateTime? now}) {
    final birth = DateTime.tryParse(dob);
    if (birth == null) return null;
    final today = now ?? DateTime.now();
    var age = today.year - birth.year;
    if (today.month < birth.month || (today.month == birth.month && today.day < birth.day)) age--;
    return age < 0 ? null : age;
  }

  // --- BMR / TDEE --------------------------------------------------------

  /// Mifflin-St Jeor. 'Other' uses the midpoint of the male/female constants.
  static double bmr({
    required String gender,
    required double weightKg,
    required double heightCm,
    required int age,
  }) {
    final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
    switch (gender.toLowerCase()) {
      case 'male':
        return base + 5;
      case 'female':
        return base - 161;
      default:
        return base - 78;
    }
  }

  static double activityFactor(String level) {
    switch (level) {
      case 'Sedentary':
        return 1.2;
      case 'Lightly Active':
        return 1.375;
      case 'Moderately Active':
        return 1.55;
      case 'Very Active':
        return 1.725;
      case 'Athlete':
        return 1.9;
      default:
        return 1.375;
    }
  }

  static double tdee(double bmr, String activityLevel) => bmr * activityFactor(activityLevel);

  // --- Calorie targets ---------------------------------------------------

  /// Deficit −500 kcal, surplus +300 kcal. The deficit is floored at the
  /// larger of BMR and 1200 (F) / 1500 (M), and not applied when underweight.
  static CalorieTargets calorieTargets({
    required double bmr,
    required double tdee,
    required String gender,
    required double bmi,
  }) {
    final maintain = tdee.round();
    final floor = [bmr, gender.toLowerCase() == 'male' ? 1500.0 : 1200.0].reduce((a, b) => a > b ? a : b);
    var deficit = (tdee - 500).round();
    String? note;
    if (bmi > 0 && bmi < 18.5) {
      deficit = maintain;
      note = 'Calorie deficit not applied because your BMI is in the underweight range.';
    } else if (deficit < floor) {
      deficit = floor.round();
      note = 'Deficit limited to ${floor.round()} kcal/day, the minimum safe intake for you.';
    }
    return CalorieTargets(
      maintain: maintain,
      deficit: deficit,
      surplus: maintain + 300,
      safetyNote: note,
    );
  }

  static int targetFor(String goal, CalorieTargets t) {
    switch (goal) {
      case 'Lose Weight':
        return t.deficit;
      case 'Gain Muscle':
        return t.surplus;
      default:
        return t.maintain;
    }
  }

  // --- Macros ------------------------------------------------------------

  /// Protein by body weight and goal, fat ~27% of calories, carbs the rest.
  /// Diabetic users have carbs capped at 40% of calories.
  static Macros macros({
    required int kcal,
    required double weightKg,
    required String goal,
    bool diabetic = false,
    bool conservativeProtein = false,
  }) {
    var perKg = goal == 'Gain Muscle' ? 1.8 : (goal == 'Lose Weight' ? 1.6 : 1.2);
    if (conservativeProtein) perKg = perKg > 1.4 ? 1.4 : perKg;
    var protein = (weightKg * perKg).round();
    // Never let protein exceed 35% of calories.
    final proteinCap = (kcal * 0.35 / 4).round();
    if (protein > proteinCap) protein = proteinCap;

    var fat = (kcal * 0.27 / 9).round();
    var carbs = ((kcal - protein * 4 - fat * 9) / 4).round();

    if (diabetic) {
      final carbCap = (kcal * 0.40 / 4).round();
      if (carbs > carbCap) {
        final extraKcal = (carbs - carbCap) * 4;
        carbs = carbCap;
        fat += (extraKcal / 9).round();
      }
    }
    if (carbs < 0) carbs = 0;
    return Macros(proteinG: protein, carbsG: carbs, fatG: fat);
  }

  /// Daily water target (litres), ~35 ml/kg rounded to the nearest 0.5.
  static double waterLitres(double weightKg) {
    final l = weightKg * 0.035;
    return ((l * 2).round() / 2).clamp(1.5, 4.0).toDouble();
  }
}
