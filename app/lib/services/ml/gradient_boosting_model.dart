import 'dart:convert';

/// Evaluates a scikit-learn GradientBoostingRegressor exported by
/// `ml/calorie_model/train.py` (trees stored as arrays). Tree ensembles have no TFLite
/// operator, so they run natively here: sum of the tree outputs times the learning rate.
class GradientBoostingModel {
  final double init;
  final double learningRate;
  final List<_Tree> _trees;
  final List<String> features;
  final List<String> workoutTypes;
  final Map<String, dynamic> metadata;

  GradientBoostingModel._(this.init, this.learningRate, this._trees, this.features, this.workoutTypes, this.metadata);

  factory GradientBoostingModel.fromJsonString(String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    List<double> doubles(dynamic v) => [for (final e in v as List) (e as num).toDouble()];
    List<int> ints(dynamic v) => [for (final e in v as List) (e as num).toInt()];
    return GradientBoostingModel._(
      (j['init'] as num).toDouble(),
      (j['learning_rate'] as num).toDouble(),
      [
        for (final t in j['trees'] as List)
          _Tree(
            left: ints((t as Map)['left']),
            right: ints(t['right']),
            feature: ints(t['feature']),
            threshold: doubles(t['threshold']),
            value: doubles(t['value']),
          ),
      ],
      [for (final f in j['features'] as List) f as String],
      [for (final f in (j['workout_types'] as List? ?? const [])) f as String],
      j,
    );
  }

  double predict(List<double> x) {
    var sum = init;
    for (final t in _trees) {
      sum += learningRate * t.predict(x);
    }
    return sum;
  }

  int get treeCount => _trees.length;
}

class _Tree {
  final List<int> left, right, feature;
  final List<double> threshold, value;
  const _Tree({required this.left, required this.right, required this.feature, required this.threshold, required this.value});

  double predict(List<double> x) {
    var node = 0;
    while (left[node] != -1) {
      node = x[feature[node]] <= threshold[node] ? left[node] : right[node];
    }
    return value[node];
  }
}

/// Workout calories from the Gradient Boosting model, using only inputs the app has.
class WorkoutCalorieModel {
  final GradientBoostingModel model;
  const WorkoutCalorieModel(this.model);

  /// [experience]: 1 beginner … 3 expert. [workoutType]: Cardio, HIIT, Strength or Yoga.
  double predictKcal({
    required double age,
    required bool male,
    required double weightKg,
    required double heightCm,
    required double durationHours,
    required int experience,
    required String workoutType,
  }) {
    final x = [
      age,
      male ? 1.0 : 0.0,
      weightKg,
      heightCm / 100,
      durationHours,
      experience.toDouble(),
      workoutType == 'Cardio' ? 1.0 : 0.0,
      workoutType == 'HIIT' ? 1.0 : 0.0,
      workoutType == 'Strength' ? 1.0 : 0.0,
      workoutType == 'Yoga' ? 1.0 : 0.0,
    ];
    final kcal = model.predict(x);
    return kcal < 0 ? 0 : kcal;
  }
}
