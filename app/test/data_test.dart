import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/food.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/services/realtime_db.dart';

/// Mimics what the Realtime Database does to a value: it keeps numbers and
/// strings, drops empty lists/maps, and hands back Map<Object?, Object?>.
Object? _throughDatabase(Object? v) {
  if (v is Map) {
    final out = <Object?, Object?>{};
    v.forEach((k, val) {
      final c = _throughDatabase(val);
      if (c != null) out[k] = c;
    });
    return out.isEmpty ? null : out;
  }
  if (v is List) {
    final out = v.map(_throughDatabase).toList();
    return out.isEmpty ? null : out;
  }
  return v;
}

void main() {
  test('plain() converts nested Map<Object?, Object?> and lists', () {
    final raw = <Object?, Object?>{
      'height': <Object?, Object?>{'value': 170, 'unit': 'cm'},
      'foodAllergies': <Object?>['Dairy', 'Nuts'],
    };
    final out = RealtimeDb.plain(raw) as Map<String, dynamic>;
    expect(out['height'], isA<Map<String, dynamic>>());
    expect((out['height'] as Map)['value'], 170);
    expect(out['foodAllergies'], ['Dairy', 'Nuts']);
  });

  test('a profile survives a round trip through the database', () {
    final original = HealthProfile(
      fullName: 'Aamna Khan',
      dob: '2000-03-15',
      gender: 'Female',
      heightValue: 165,
      weightValue: 72.5,
      medicalConditions: ['Asthma'],
      foodAllergies: ['Dairy', 'Nuts'],
      primaryGoal: 'Lose Weight',
      activityLevel: 'Lightly Active',
      workoutFrequency: 4,
      targetWeightValue: 65,
      calculatedBMI: 26.6,
      healthClassification: 'At-Risk',
      planVariant: 2,
    );
    final stored = _throughDatabase(original.toJson());
    final loaded = HealthProfile.fromJson(Map<String, dynamic>.from(RealtimeDb.plain(stored) as Map));

    expect(loaded.fullName, original.fullName);
    expect(loaded.dob, original.dob);
    expect(loaded.weightValue, 72.5);
    expect(loaded.medicalConditions, ['Asthma']);
    expect(loaded.foodAllergies, ['Dairy', 'Nuts']);
    expect(loaded.healthClassification, 'At-Risk');
    expect(loaded.planVariant, 2);
    expect(loaded.bmi, closeTo(original.bmi, 0.001));
  });

  test('a profile with empty lists and blank fields loads without errors', () {
    final stored = _throughDatabase(HealthProfile(fullName: 'New User', heightValue: 170, weightValue: 70).toJson());
    final loaded = HealthProfile.fromJson(Map<String, dynamic>.from(RealtimeDb.plain(stored) as Map));

    expect(loaded.medicalConditions, isEmpty);
    expect(loaded.foodAllergies, isEmpty);
    expect(loaded.age, isNull);
    expect(loaded.heightUnit, 'cm');
  });

  test('food entries keep their id and date after loading', () {
    const entry = FoodEntry(
      date: '2026-10-12', meal: 'Lunch', name: 'Daal', quantity: 1.5, unit: 'serving',
      kcal: 345, protein: 21, carbs: 49.5, fat: 7.5,
    );
    final stored = Map<String, dynamic>.from(entry.toJson())..remove('date');
    final loaded = FoodEntry.fromJson({...stored, 'id': '-Nabc123', 'date': '2026-10-12'});

    expect(loaded.id, '-Nabc123');
    expect(loaded.date, '2026-10-12');
    expect(loaded.kcal, 345);
    expect(loaded.quantity, 1.5);
  });
}
