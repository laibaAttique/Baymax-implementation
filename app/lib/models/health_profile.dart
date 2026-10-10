import '../utils/health_calc.dart';

class HealthProfile {
  String fullName;

  /// ISO date, `YYYY-MM-DD`.
  String dob;
  String gender;
  double heightValue;
  String heightUnit;
  double weightValue;
  String weightUnit;
  List<String> medicalConditions;
  List<String> foodAllergies;
  String medications;
  String primaryGoal;
  String activityLevel;
  int workoutFrequency;
  double targetWeightValue;
  String targetWeightUnit;
  double calculatedBMI;

  /// Module 2 result (Healthy / Overweight / Obese / At-Risk / Cardiac / Diabetic).
  String healthClassification;

  /// Module 3: which generated variant of the plan the user is on (FE-7).
  int planVariant;

  HealthProfile({
    this.fullName = '',
    this.dob = '',
    this.gender = '',
    this.heightValue = 0,
    this.heightUnit = 'cm',
    this.weightValue = 0,
    this.weightUnit = 'kg',
    this.medicalConditions = const [],
    this.foodAllergies = const [],
    this.medications = '',
    this.primaryGoal = '',
    this.activityLevel = '',
    this.workoutFrequency = 4,
    this.targetWeightValue = 0,
    this.targetWeightUnit = 'kg',
    this.calculatedBMI = 0,
    this.healthClassification = '',
    this.planVariant = 0,
  });

  // --- Derived values (metric) -------------------------------------------

  double get heightCm => HealthCalc.toCm(heightValue, heightUnit);
  double get weightKg => HealthCalc.toKg(weightValue, weightUnit);
  double get targetWeightKg => HealthCalc.toKg(targetWeightValue, targetWeightUnit);
  int? get age => HealthCalc.ageFromDob(dob);
  double get bmi => HealthCalc.bmi(weightKg, heightCm);
  String get bmiCategory => HealthCalc.whoCategory(bmi);

  /// Age used for calculations; falls back to 30 for profiles saved before
  /// date of birth was collected.
  int get ageForCalc => age ?? 30;

  double get bmr => HealthCalc.bmr(
        gender: gender,
        weightKg: weightKg,
        heightCm: heightCm,
        age: ageForCalc,
      );

  double get tdee => HealthCalc.tdee(bmr, activityLevel);

  CalorieTargets get calorieTargets =>
      HealthCalc.calorieTargets(bmr: bmr, tdee: tdee, gender: gender, bmi: bmi);

  int get dailyCalorieTarget => HealthCalc.targetFor(primaryGoal, calorieTargets);

  bool hasCondition(String condition) =>
      medicalConditions.any((c) => c.toLowerCase() == condition.toLowerCase());

  /// Allergies the user actually selected (drops the "None"/"Other" chips).
  List<String> get allergies =>
      foodAllergies.where((a) => a != 'None' && a != 'Other' && a.trim().isNotEmpty).toList();

  // --- Serialisation -----------------------------------------------------

  Map<String, dynamic> toJson() {
    return {
      'fullName': fullName,
      'dob': dob,
      'gender': gender,
      'height': {'value': heightValue, 'unit': heightUnit},
      'weight': {'value': weightValue, 'unit': weightUnit},
      'medicalConditions': medicalConditions,
      'foodAllergies': foodAllergies,
      'medications': medications,
      'primaryGoal': primaryGoal,
      'activityLevel': activityLevel,
      'workoutFrequency': workoutFrequency,
      'targetWeight': {'value': targetWeightValue, 'unit': targetWeightUnit},
      'calculatedBMI': calculatedBMI,
      'healthClassification': healthClassification,
      'planVariant': planVariant,
    };
  }

  factory HealthProfile.fromJson(Map<String, dynamic> json) {
    double num0(dynamic v) => (v as num?)?.toDouble() ?? 0;
    List<String> list(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : <String>[];
    final height = (json['height'] as Map?) ?? const {};
    final weight = (json['weight'] as Map?) ?? const {};
    final target = (json['targetWeight'] as Map?) ?? const {};

    return HealthProfile(
      fullName: json['fullName'] as String? ?? '',
      dob: json['dob'] as String? ?? '',
      gender: json['gender'] as String? ?? '',
      heightValue: num0(height['value']),
      heightUnit: height['unit'] as String? ?? 'cm',
      weightValue: num0(weight['value']),
      weightUnit: weight['unit'] as String? ?? 'kg',
      medicalConditions: list(json['medicalConditions']),
      foodAllergies: list(json['foodAllergies']),
      medications: json['medications'] as String? ?? '',
      primaryGoal: json['primaryGoal'] as String? ?? '',
      activityLevel: json['activityLevel'] as String? ?? '',
      workoutFrequency: (json['workoutFrequency'] as num?)?.toInt() ?? 4,
      targetWeightValue: num0(target['value']),
      targetWeightUnit: target['unit'] as String? ?? 'kg',
      calculatedBMI: num0(json['calculatedBMI']),
      healthClassification: json['healthClassification'] as String? ?? '',
      planVariant: (json['planVariant'] as num?)?.toInt() ?? 0,
    );
  }
}
