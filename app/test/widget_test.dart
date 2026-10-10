import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/health_profile.dart';

void main() {
  test('HealthProfile.toJson nests height/weight with units', () {
    final json = HealthProfile(
      fullName: 'Test User',
      heightValue: 170,
      weightValue: 65,
      calculatedBMI: 22.5,
    ).toJson();

    expect(json['fullName'], 'Test User');
    expect(json['height'], {'value': 170.0, 'unit': 'cm'});
    expect(json['weight'], {'value': 65.0, 'unit': 'kg'});
    expect(json['calculatedBMI'], 22.5);
  });
}
