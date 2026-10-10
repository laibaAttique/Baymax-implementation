import 'dart:convert';
import 'dart:typed_data';
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

  /// Most likely foods, best first (empty when unsure or unavailable).
  Future<List<FoodGuess>> classify(Uint8List imageBytes, {int topK = 3});
}

/// Used until the trained model file is added to `assets/models/`.
class UnavailableFoodImageClassifier implements FoodImageClassifier {
  const UnavailableFoodImageClassifier();

  @override
  bool get available => false;

  @override
  Future<List<FoodGuess>> classify(Uint8List imageBytes, {int topK = 3}) async => const [];
}

/// MobileNetV2 food classifier running on-device with TensorFlow Lite.
/// Trained by `ml/food_classifier/train_kaggle.py`; needs two files in `assets/models/`:
///   food_classifier.tflite and food_classifier_labels.json
class TfliteFoodClassifier implements FoodImageClassifier {
  final Interpreter _interpreter;
  final List<String> labels;
  final int inputSize;
  final Map<String, dynamic> metadata;

  TfliteFoodClassifier._(this._interpreter, this.labels, this.inputSize, this.metadata);

  /// Returns the real classifier if the model files are bundled, otherwise the unavailable one.
  static Future<FoodImageClassifier> load() async {
    try {
      final meta = jsonDecode(await rootBundle.loadString('assets/models/food_classifier_labels.json')) as Map<String, dynamic>;
      final interpreter = await Interpreter.fromAsset('assets/models/food_classifier.tflite');
      return TfliteFoodClassifier._(
        interpreter,
        [for (final l in meta['labels'] as List) l as String],
        ((meta['input'] as Map?)?['size'] as num?)?.toInt() ?? 224,
        meta,
      );
    } catch (_) {
      return const UnavailableFoodImageClassifier();
    }
  }

  @override
  bool get available => true;

  @override
  Future<List<FoodGuess>> classify(Uint8List imageBytes, {int topK = 3}) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return const [];
    final resized = img.copyResize(decoded, width: inputSize, height: inputSize, interpolation: img.Interpolation.average);

    // The model rescales to [-1, 1] itself, so it takes raw 0..255 RGB values.
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
