import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// One candidate food for a photo. [foodId] is an id in the food catalogue.
class FoodGuess {
  final String foodId;
  final double confidence;
  const FoodGuess(this.foodId, this.confidence);
}

/// Module 7 (FE-8/FE-9): recognises the food in a photo.
abstract class FoodImageClassifier {
  bool get available;

  /// Lowest confidence at which a guess is offered to the user.
  double get minConfidence => 0.35;

  /// True when the model has NOT passed its shipping gate and is only loaded for testing (debug/profile builds).
  bool get experimental => false;

  /// Foods the model got right less than [FoodModelInfo.minClassRecall] of the time on held-out photos.
  Set<String> get weakLabels => const {};

  /// Most likely foods, best first (empty when unsure or unavailable).
  Future<List<FoodGuess>> classify(Uint8List imageBytes, {int topK = 3});
}

/// Used until the trained model file is added to `assets/models/`.
class UnavailableFoodImageClassifier implements FoodImageClassifier {
  const UnavailableFoodImageClassifier();

  @override
  bool get available => false;

  @override
  double get minConfidence => 0.35;

  @override
  bool get experimental => false;

  @override
  Set<String> get weakLabels => const {};

  @override
  Future<List<FoodGuess>> classify(Uint8List imageBytes, {int topK = 3}) async => const [];
}

/// What the training notebook recorded about a model file (`food_classifier_labels.json`).
class FoodModelInfo {
  /// A food whose recall on held-out photos is below this fails the shipping gate (same value as the notebook).
  static const minClassRecall = 0.70;

  final List<String> labels;
  final int inputSize;
  final double minConfidence;

  /// The notebook's shipping gate (accuracy, every-class recall, TFLite parity) passed.
  final bool passedGate;
  final Set<String> weakLabels;
  final double? testTop1;

  const FoodModelInfo({
    required this.labels,
    required this.inputSize,
    required this.minConfidence,
    required this.passedGate,
    required this.weakLabels,
    this.testTop1,
  });

  factory FoodModelInfo.fromJson(Map<String, dynamic> m) {
    final perClass = ((m['metrics'] as Map?)?['per_class'] as Map?) ?? const {};
    return FoodModelInfo(
      labels: [for (final l in m['labels'] as List) l as String],
      inputSize: ((m['input'] as Map?)?['size'] as num?)?.toInt() ?? 224,
      minConfidence: (m['recommended_min_confidence'] as num?)?.toDouble() ?? 0.5,
      passedGate: m['ship_recommended'] == true,
      weakLabels: {
        for (final e in perClass.entries)
          if (((e.value as Map)['recall'] as num?) != null && ((e.value as Map)['recall'] as num) < minClassRecall) e.key as String,
      },
      testTop1: ((m['metrics'] as Map?)?['test_top1'] as num?)?.toDouble(),
    );
  }
}

/// Food classifier (EfficientNetV2-B0, float16) running on-device with TensorFlow Lite.
/// Trained by `module7_food_model_kaggle.ipynb`; needs two files in `assets/models/`:
///   food_classifier.tflite and food_classifier_labels.json
///
/// Rule: a model that did not pass the notebook's shipping gate (`ship_recommended: false`) is only used in
/// debug/profile builds, with an "experimental" banner. A release build ignores it and the user picks the food.
class TfliteFoodClassifier implements FoodImageClassifier {
  final Interpreter _interpreter;
  final FoodModelInfo info;

  TfliteFoodClassifier._(this._interpreter, this.info);

  List<String> get labels => info.labels;
  int get inputSize => info.inputSize;

  /// Returns the real classifier if the model files are bundled (and allowed), otherwise the unavailable one.
  /// [allowUnvalidated] defaults to "not a release build".
  static Future<FoodImageClassifier> load({bool? allowUnvalidated}) async {
    try {
      final meta = jsonDecode(await rootBundle.loadString('assets/models/food_classifier_labels.json')) as Map<String, dynamic>;
      final info = FoodModelInfo.fromJson(meta);
      if (!info.passedGate && !(allowUnvalidated ?? !kReleaseMode)) return const UnavailableFoodImageClassifier();
      final interpreter = await Interpreter.fromAsset('assets/models/food_classifier.tflite');
      return TfliteFoodClassifier._(interpreter, info);
    } catch (_) {
      return const UnavailableFoodImageClassifier();
    }
  }

  @override
  bool get available => true;

  @override
  bool get experimental => !info.passedGate;

  @override
  Set<String> get weakLabels => info.weakLabels;

  /// Chosen from the held-out test set during training (precision of about 90% or better).
  @override
  double get minConfidence => info.minConfidence;

  @override
  Future<List<FoodGuess>> classify(Uint8List imageBytes, {int topK = 3}) async {
    final raw = img.decodeImage(imageBytes);
    if (raw == null) return const [];
    final decoded = img.bakeOrientation(raw); // phone photos carry a rotation flag; the model was trained upright
    final resized = img.copyResize(decoded, width: inputSize, height: inputSize, interpolation: img.Interpolation.average);

    // The preprocessing is inside the model, so it takes raw 0..255 RGB values.
    final input = [
      List.generate(inputSize, (y) => List.generate(inputSize, (x) {
            final p = resized.getPixel(x, y);
            return [p.r.toDouble(), p.g.toDouble(), p.b.toDouble()];
          })),
    ];
    final output = [List<double>.filled(labels.length, 0)];
    _interpreter.run(input, output);

    final scores = output.first;
    final order = List<int>.generate(scores.length, (i) => i)..sort((a, b) => scores[b].compareTo(scores[a]));
    return [for (final i in order.take(topK)) FoodGuess(labels[i], scores[i])];
  }

  void close() => _interpreter.close();
}
