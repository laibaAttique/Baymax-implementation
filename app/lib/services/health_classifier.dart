import '../models/health_profile.dart';
import 'ml/health_risk_model.dart';

/// Module 2 output (FE-4): one of Healthy, Overweight, Obese, At-Risk,
/// Cardiac, Diabetic.
class ClassificationResult {
  final String category;
  final String riskLevel; // Low / Moderate / High
  final String bmiCategory; // WHO category
  final double bmi;
  final List<String> riskFactors;

  /// Short explanation of why this category was chosen.
  final String rationale;

  /// How the result was produced ("WHO rules + medical rules" today; the
  /// Logistic Regression model replaces this in phase 2).
  final String method;

  /// Estimated share of similar people (same BMI, age, sex, activity) with each condition,
  /// from the Logistic Regression model, and the average for the whole survey population.
  /// Empty when the model is not available.
  final Map<String, double> modelRisk;
  final Map<String, double> modelBaseline;

  const ClassificationResult({
    required this.category,
    required this.riskLevel,
    required this.bmiCategory,
    required this.bmi,
    required this.riskFactors,
    required this.rationale,
    required this.method,
    this.modelRisk = const {},
    this.modelBaseline = const {},
  });

  bool get hasModelInsight => modelRisk.isNotEmpty;

  bool get isCardiac => category == 'Cardiac';
  bool get isDiabetic => category == 'Diabetic';
}

/// Phase 2 seam: implement this with the trained Logistic Regression model.
abstract class HealthClassifier {
  ClassificationResult classify(HealthProfile profile);
}

/// FE-1/FE-2: inputs BMI, age, gender, activity level (+ medical history),
/// WHO BMI rules, with medical conditions taking precedence.
class RuleBasedClassifier implements HealthClassifier {
  const RuleBasedClassifier();

  static const categories = ['Healthy', 'Overweight', 'Obese', 'At-Risk', 'Cardiac', 'Diabetic'];

  @override
  ClassificationResult classify(HealthProfile p) {
    final bmi = p.bmi;
    final who = p.bmiCategory;
    final age = p.age;
    final sedentary = p.activityLevel == 'Sedentary';

    final heart = p.hasCondition('Heart Disease');
    final diabetes = p.hasCondition('Diabetes');
    final hypertension = p.hasCondition('Hypertension');
    final asthma = p.hasCondition('Asthma');
    final pcos = p.hasCondition('PCOS');
    final obesityListed = p.hasCondition('Obesity');
    final underweight = bmi > 0 && bmi < 18.5;
    final obese = bmi >= 30;
    final overweight = bmi >= 25 && bmi < 30;
    final senior = age != null && age >= 60;

    // Risk factors shown to the user.
    final factors = <String>[];
    if (heart) factors.add('Heart disease');
    if (diabetes) factors.add('Diabetes');
    if (hypertension) factors.add('Hypertension');
    if (asthma) factors.add('Asthma');
    if (pcos) factors.add('PCOS');
    if (underweight) factors.add('Underweight BMI');
    if (overweight || obese || obesityListed) factors.add('Elevated BMI (${bmi.toStringAsFixed(1)})');
    if (sedentary) factors.add('Sedentary lifestyle');
    if (senior) factors.add('Age 60+');
    for (final a in p.allergies) {
      factors.add('$a allergy');
    }

    String category;
    String risk;
    String why;

    if (heart) {
      category = 'Cardiac';
      risk = 'High';
      why = 'You reported heart disease, so cardiac safety rules override BMI-based categories.';
    } else if (diabetes) {
      category = 'Diabetic';
      risk = 'High';
      why = 'You reported diabetes, so blood-sugar-aware rules are applied to your plans.';
    } else if (hypertension ||
        asthma ||
        pcos ||
        underweight ||
        (obesityListed && !obese) ||
        (senior && sedentary)) {
      category = 'At-Risk';
      risk = (hypertension && obese) || bmi >= 35 || (underweight && bmi < 17) ? 'High' : 'Moderate';
      why = 'A reported condition or your BMI/age/activity combination puts you in the at-risk group.';
    } else if (obese) {
      category = 'Obese';
      risk = bmi >= 35 ? 'High' : 'Moderate';
      why = 'Your BMI of ${bmi.toStringAsFixed(1)} falls in the WHO obese range (30 or above).';
    } else if (overweight) {
      category = 'Overweight';
      risk = 'Moderate';
      why = 'Your BMI of ${bmi.toStringAsFixed(1)} falls in the WHO overweight range (25–29.9).';
    } else {
      category = 'Healthy';
      risk = 'Low';
      why = 'Your BMI of ${bmi.toStringAsFixed(1)} is in the WHO normal range and no risk conditions were reported.';
    }

    return ClassificationResult(
      category: category,
      riskLevel: risk,
      bmiCategory: who,
      bmi: bmi,
      riskFactors: factors,
      rationale: why,
      method: 'WHO BMI rules + medical-condition rules',
    );
  }
}

/// Module 2 (FE-1..FE-5) with the trained Logistic Regression (FE-3):
///  1. The rule engine decides first — reported conditions and WHO BMI bands always win.
///  2. The model adds a statistical risk estimate for diabetes and heart disease.
///  3. If nothing was reported but the model's risk for someone like this is well above the
///     population average (thresholds chosen at training time), the category becomes At-Risk.
/// The model never assigns "Cardiac" or "Diabetic" on its own: only a reported diagnosis does.
class HybridHealthClassifier implements HealthClassifier {
  final RuleBasedClassifier rules;
  final HealthRiskModel model;
  const HybridHealthClassifier(this.rules, this.model);

  @override
  ClassificationResult classify(HealthProfile p) {
    final base = rules.classify(p);
    if (p.bmi <= 0) return base;

    final sexMale = p.gender.toLowerCase() == 'male' ? 1.0 : (p.gender.toLowerCase() == 'female' ? 0.0 : 0.5);
    final active = p.activityLevel == 'Sedentary' ? 0.0 : 1.0;
    final all = model.predictCalibrated(bmi: p.bmi, age: p.ageForCalc.toDouble(), sexMale: sexMale, active: active);
    final risk = {'Diabetic': all['Diabetic']!, 'Cardiac': all['Cardiac']!};
    final baseline = {'Diabetic': model.baseRates['Diabetic']!, 'Cardiac': model.baseRates['Cardiac']!};

    var category = base.category;
    var level = base.riskLevel;
    var rationale = base.rationale;
    final factors = [...base.riskFactors];

    final noReportedRisk = const {'Healthy', 'Overweight', 'Obese'}.contains(base.category);
    if (noReportedRisk) {
      final flagged = <String>[];
      final dThr = model.thresholds['Diabetic'];
      final cThr = model.thresholds['Cardiac'];
      if (dThr != null && risk['Diabetic']! >= dThr) {
        flagged.add('diabetes (${(risk['Diabetic']! * 100).round()}% vs ${(baseline['Diabetic']! * 100).round()}% average)');
      }
      if (cThr != null && risk['Cardiac']! >= cThr) {
        flagged.add('heart disease (${(risk['Cardiac']! * 100).round()}% vs ${(baseline['Cardiac']! * 100).round()}% average)');
      }
      if (flagged.isNotEmpty) {
        category = 'At-Risk';
        if (level == 'Low') level = 'Moderate';
        factors.add('Statistical risk of ${flagged.join(' and ')}');
        rationale = 'No condition was reported, but people with your BMI, age, sex and activity level show a clearly '
            'higher-than-average rate of ${flagged.join(' and ')} in a large health survey, so you are placed in the at-risk group. '
            'This is a screening estimate, not a diagnosis.';
      }
    }

    return ClassificationResult(
      category: category,
      riskLevel: level,
      bmiCategory: base.bmiCategory,
      bmi: base.bmi,
      riskFactors: factors,
      rationale: rationale,
      method: 'WHO BMI rules + medical-condition rules + Logistic Regression (CDC BRFSS survey, v${model.version})',
      modelRisk: risk,
      modelBaseline: baseline,
    );
  }
}
