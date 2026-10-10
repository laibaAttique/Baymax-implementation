import 'dart:convert';
import 'dart:math' as math;

/// On-device Logistic Regression for Module 2 (FE-3), trained by
/// `ml/health_classifier/train.py` on the CDC BRFSS survey data.
///
/// The weights are loaded from `assets/models/health_classifier.json`; the same model is
/// also exported as `health_classifier.tflite`. It is evaluated here in plain Dart
/// (a handful of multiplications), which keeps it unit-testable against the
/// exact numbers produced during training.
class HealthRiskModel {
  final List<String> classes;
  final List<double> mean;
  final List<double> scale;
  final List<List<double>> coef;
  final List<double> intercept;
  final List<double> priors;

  /// Calibrated-probability thresholds above which a risk is flagged, per class
  /// (`null` when the model could not reach a useful precision).
  final Map<String, double?> thresholds;
  final String version;
  final Map<String, dynamic> metadata;

  HealthRiskModel({
    required this.classes,
    required this.mean,
    required this.scale,
    required this.coef,
    required this.intercept,
    required this.priors,
    required this.thresholds,
    required this.version,
    required this.metadata,
  });

  factory HealthRiskModel.fromJsonString(String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    List<double> doubles(dynamic v) => [for (final e in v as List) (e as num).toDouble()];
    return HealthRiskModel(
      classes: [for (final c in j['classes'] as List) c as String],
      mean: doubles(j['mean']),
      scale: doubles(j['scale']),
      coef: [for (final row in j['coef'] as List) doubles(row)],
      intercept: doubles(j['intercept']),
      priors: doubles(j['priors']),
      thresholds: {
        for (final e in (j['thresholds'] as Map<String, dynamic>).entries) e.key: (e.value as num?)?.toDouble(),
      },
      version: j['version'] as String? ?? '',
      metadata: j,
    );
  }

  /// Feature vector in the order used during training:
  /// bmi, age, sex_male, active, bmi², age².
  static List<double> features(double bmi, double age, double sexMale, double active) =>
      [bmi, age, sexMale, active, bmi * bmi, age * age];

  /// Probabilities from the class-balanced model (what scikit-learn's `predict_proba` returns).
  List<double> predictBalanced({required double bmi, required double age, required double sexMale, required double active}) {
    final x = features(bmi, age, sexMale, active);
    final z = [for (var i = 0; i < x.length; i++) (x[i] - mean[i]) / scale[i]];
    final logits = [
      for (var c = 0; c < classes.length; c++)
        intercept[c] + [for (var i = 0; i < z.length; i++) coef[c][i] * z[i]].fold(0.0, (a, b) => a + b),
    ];
    final maxLogit = logits.reduce(math.max);
    final exps = [for (final l in logits) math.exp(l - maxLogit)];
    final sum = exps.fold(0.0, (a, b) => a + b);
    return [for (final e in exps) e / sum];
  }

  /// Calibrated probabilities: undo the class-weight balancing with the training priors, so the
  /// numbers read as "share of people like this who are in each group".
  Map<String, double> predictCalibrated({required double bmi, required double age, required double sexMale, required double active}) {
    final p = predictBalanced(bmi: bmi, age: age, sexMale: sexMale, active: active);
    final q = [for (var i = 0; i < p.length; i++) p[i] * priors[i]];
    final sum = q.fold(0.0, (a, b) => a + b);
    return {for (var i = 0; i < classes.length; i++) classes[i]: q[i] / sum};
  }

  Map<String, double> get baseRates => {for (var i = 0; i < classes.length; i++) classes[i]: priors[i]};

  String get dataSourceName => (metadata['data'] as Map?)?['name'] as String? ?? 'unknown';
}
