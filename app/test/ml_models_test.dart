import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/plan_generator.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/ml/gradient_boosting_model.dart';
import 'package:app/services/ml/health_risk_model.dart';

HealthProfile person({
  String gender = 'Male',
  double height = 175,
  double weight = 70,
  int age = 30,
  List<String> conditions = const [],
  String activity = 'Moderately Active',
}) {
  final dob = DateTime(DateTime.now().year - age, 1, 1).toIso8601String().substring(0, 10);
  return HealthProfile(
    fullName: 'T', dob: dob, gender: gender, heightValue: height, weightValue: weight,
    medicalConditions: conditions, activityLevel: activity, primaryGoal: 'Maintain & Stay Fit',
  );
}

void main() {
  group('Logistic Regression health model (Module 2, FE-3)', () {
    late HealthRiskModel model;
    late String raw;
    setUpAll(() {
      raw = File('assets/models/health_classifier.json').readAsStringSync();
      model = HealthRiskModel.fromJsonString(raw);
    });

    test('Dart output matches scikit-learn exactly on the exported test vectors', () {
      final vectors = (jsonDecode(raw) as Map)['test_vectors'] as List;
      expect(vectors, isNotEmpty);
      for (final v in vectors) {
        final args = (bmi: (v['bmi'] as num).toDouble(), age: (v['age'] as num).toDouble(), sex: (v['sex_male'] as num).toDouble(), active: (v['active'] as num).toDouble());
        final balanced = model.predictBalanced(bmi: args.bmi, age: args.age, sexMale: args.sex, active: args.active);
        final calibrated = model.predictCalibrated(bmi: args.bmi, age: args.age, sexMale: args.sex, active: args.active);
        for (var i = 0; i < model.classes.length; i++) {
          expect(balanced[i], closeTo((v['proba_balanced'] as List)[i] as double, 1e-9));
          expect(calibrated[model.classes[i]]!, closeTo((v['proba_calibrated'] as List)[i] as double, 1e-9));
        }
      }
    });

    test('probabilities are valid and risk rises with age and BMI', () {
      final young = model.predictCalibrated(bmi: 22, age: 25, sexMale: 0, active: 1);
      final older = model.predictCalibrated(bmi: 38, age: 70, sexMale: 1, active: 0);
      expect(young.values.fold(0.0, (a, b) => a + b), closeTo(1, 1e-9));
      expect(older['Diabetic']!, greaterThan(young['Diabetic']!));
      expect(older['Cardiac']!, greaterThan(young['Cardiac']!));
    });

    test('model metadata documents its data source and limits', () {
      expect(model.dataSourceName, contains('CDC'));
      expect((model.metadata['limitations'] as List), isNotEmpty);
      expect(model.thresholds['Diabetic'], isNotNull);
    });
  });

  group('Hybrid classifier (rules decide, model adds risk estimates)', () {
    late HybridHealthClassifier hybrid;
    setUpAll(() {
      hybrid = HybridHealthClassifier(
        const RuleBasedClassifier(),
        HealthRiskModel.fromJsonString(File('assets/models/health_classifier.json').readAsStringSync()),
      );
    });

    test('reported conditions are never overridden by the model', () {
      expect(hybrid.classify(person(conditions: ['Heart Disease'])).category, 'Cardiac');
      expect(hybrid.classify(person(conditions: ['Diabetes'])).category, 'Diabetic');
    });

    test('a young, active, normal-weight person stays Healthy with low model risk', () {
      final r = hybrid.classify(person(age: 24, weight: 65, gender: 'Female'));
      expect(r.category, 'Healthy');
      expect(r.hasModelInsight, isTrue);
      expect(r.modelRisk['Diabetic']!, lessThan(r.modelBaseline['Diabetic']! * 1.5));
    });

    test('the model raises a flag the rules alone would miss (obese 58-year-old, nothing reported)', () {
      final p = person(age: 58, weight: 117, height: 175, activity: 'Lightly Active');
      expect(const RuleBasedClassifier().classify(p).category, 'Obese'); // rules alone
      final r = hybrid.classify(p);
      expect(r.category, 'At-Risk'); // model: ~21% diabetes risk vs 11% average
      expect(r.riskFactors.join(' '), contains('Statistical risk'));
      expect(r.rationale, contains('not a diagnosis'));
      expect(r.method, contains('Logistic Regression'));
    });

    test('a 45-year-old with the same BMI is not flagged (risk below the line)', () {
      final r = hybrid.classify(person(age: 45, weight: 117, height: 175, activity: 'Lightly Active'));
      expect(r.category, 'Obese');
    });

    test('the model alone never produces Cardiac or Diabetic', () {
      for (final age in [30, 50, 70, 85]) {
        for (final w in [60.0, 90.0, 130.0]) {
          final c = hybrid.classify(person(age: age, weight: w, activity: 'Sedentary')).category;
          expect(['Healthy', 'Overweight', 'Obese', 'At-Risk'], contains(c));
        }
      }
    });

    test('the hybrid is never LESS cautious than the rules alone', () {
      const rank = {'Healthy': 0, 'Overweight': 1, 'Obese': 2, 'At-Risk': 3, 'Diabetic': 4, 'Cardiac': 5};
      for (final age in [25, 45, 65]) {
        for (final w in [55.0, 80.0, 110.0]) {
          final p = person(age: age, weight: w);
          expect(rank[hybrid.classify(p).category]!, greaterThanOrEqualTo(rank[const RuleBasedClassifier().classify(p).category]!));
        }
      }
    });
  });

  group('Gradient Boosting evaluator (Module 3, FR-4)', () {
    test('matches scikit-learn on a synthetic fixture', () {
      final raw = File('test/fixtures/tiny_gb.json').readAsStringSync();
      final model = GradientBoostingModel.fromJsonString(raw);
      final vectors = (jsonDecode(raw) as Map)['test_vectors'] as List;
      expect(model.treeCount, 40);
      for (final v in vectors) {
        final x = [for (final e in v['x'] as List) (e as num).toDouble()];
        expect(model.predict(x), closeTo((v['kcal'] as num).toDouble(), 1e-6));
      }
    });

    test('WorkoutCalorieModel builds features in the training order and never goes negative', () {
      final model = WorkoutCalorieModel(GradientBoostingModel.fromJsonString(File('test/fixtures/tiny_gb.json').readAsStringSync()));
      final heavier = model.predictKcal(age: 30, male: true, weightKg: 100, heightCm: 180, durationHours: 1, experience: 2, workoutType: 'Cardio');
      final lighter = model.predictKcal(age: 30, male: true, weightKg: 55, heightCm: 180, durationHours: 1, experience: 2, workoutType: 'Cardio');
      expect(heavier, greaterThan(lighter));
      expect(model.predictKcal(age: 30, male: false, weightKg: 40, heightCm: 150, durationHours: 0, experience: 1, workoutType: 'Yoga'), greaterThanOrEqualTo(0));
    });
  });

  group('Calorie model plugged into the plan generator', () {
    test('uses the model estimate when a model is provided, MET otherwise', () {
      final foods = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
      ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
      final p = person(age: 30, weight: 70).. primaryGoal = 'Lose Weight'..workoutFrequency = 4;
      final cls = const RuleBasedClassifier().classify(p);

      final plain = PlanGenerator(foods).generate(p, cls);
      expect(plain.week.whereType<WorkoutDay>().every((d) => d.modelKcal == null), isTrue);

      final withModel = PlanGenerator(
        foods,
        workoutModel: WorkoutCalorieModel(GradientBoostingModel.fromJsonString(File('test/fixtures/tiny_gb.json').readAsStringSync())),
      ).generate(p, cls);
      final days = withModel.week.whereType<WorkoutDay>().toList();
      expect(days, isNotEmpty);
      for (final d in days) {
        expect(d.modelKcal, isNotNull);
        expect(d.kcal(p.weightKg), d.modelKcal);
        expect(d.metKcal(p.weightKg), greaterThan(0));
        expect(['Cardio', 'HIIT', 'Strength', 'Yoga'], contains(d.kind));
      }
    });
  });
}
