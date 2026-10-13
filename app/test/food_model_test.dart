import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/food_image_classifier.dart';

void main() {
  final meta = jsonDecode(File('assets/models/food_classifier_labels.json').readAsStringSync()) as Map<String, dynamic>;
  final info = FoodModelInfo.fromJson(meta);

  test('bundled food model metadata is read correctly', () {
    expect(info.labels.length, 22);
    expect(info.inputSize, 256);
    expect(info.minConfidence, 0.3);
    expect(info.testTop1, closeTo(0.926, 0.001));
  });

  test('the model that failed its shipping gate is flagged experimental, with its weak foods named', () {
    expect(info.passedGate, isFalse);
    expect(info.weakLabels, {'aloo_gobi', 'paratha'});
  });

  test('every food the model can predict exists in the food catalogue', () {
    final catalogue = jsonDecode(File('assets/data/foods.json').readAsStringSync());
    final items = (catalogue is List ? catalogue : catalogue['foods']) as List;
    final ids = {for (final i in items) (i as Map)['id'] as String};
    expect(info.labels.where((l) => !ids.contains(l)), isEmpty);
  });

  test('a model that passed the gate is not experimental and a missing recall is not weak', () {
    final ok = FoodModelInfo.fromJson({
      'labels': ['a', 'b'],
      'ship_recommended': true,
      'metrics': {
        'per_class': {
          'a': {'recall': 0.9},
          'b': {'recall': 0.7},
        }
      },
    });
    expect(ok.passedGate, isTrue);
    expect(ok.weakLabels, isEmpty); // exactly 70% meets the bar
    expect(ok.inputSize, 224); // default when the file does not say
    expect(ok.minConfidence, 0.5);
  });

  test('without ship_recommended the model is treated as not validated', () {
    final unknown = FoodModelInfo.fromJson({'labels': ['a']});
    expect(unknown.passedGate, isFalse);
  });
}
