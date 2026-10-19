// All real-device cases in one app launch (one build and one install instead of five).
//   bash integration_test/run_on_device.sh integration_test/all_device_test.dart <run-name>
// Each file can also be run on its own.
import 'cross_module_test.dart' as cross;
import 'helpers/test_app.dart';
import 'module4_workout_test.dart' as m4;
import 'module5_posture_test.dart' as m5;
import 'module6_voice_test.dart' as m6;
import 'smoke_test.dart' as smoke;

void main() {
  binding;
  smoke.smokeTests();
  m4.module4Tests();
  m5.module5Tests();
  m6.module6Tests();
  cross.crossModuleTests();
}
