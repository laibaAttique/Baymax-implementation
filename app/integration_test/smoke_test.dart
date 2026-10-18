// Real-device smoke test: the app's signed-in shell starts on the phone, Home appears, a real navigation control is tapped,
// the destination appears, and navigating back returns Home.
//   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/smoke_test.dart -d <device-id>
import 'package:flutter_test/flutter_test.dart';

import 'helpers/navigation_helpers.dart';
import 'helpers/test_app.dart';

void main() {
  binding;
  smokeTests();
}

void smokeTests() {
  group('Smoke (real device)', () {
    deviceCase('ATC-DEV-S01', req: 'M3-FR7', file: 'smoke_test.dart',
        objective: 'The app shell starts on the phone and the bottom navigation opens the Workout tab and returns Home',
        input: 'Controlled test user "Device Tester" (in memory); tap "Workout", then "Home"',
        expected: "Home shows \"TODAY'S WORKOUT\"; Workout tab shows \"Your workout plan\"; Home shown again",
        body: (t) async {
          await startControlledSession(t);
          await launchApp(t);
          await waitFor(t, find.text("TODAY'S WORKOUT").hitTestable(), what: 'the Home dashboard');
          final home = count(find.text('Device'));
          await tapOn(t, navTab('Workout'), what: 'the Workout tab');
          await waitFor(t, find.text('Your workout plan').hitTestable(), what: 'the workout plan on screen');
          final plan = count(find.text('Your workout plan'));
          await tapOn(t, navTab('Home'), what: 'the Home tab');
          await waitFor(t, find.text("TODAY'S WORKOUT").hitTestable(), what: 'Home again');
          return Outcome(plan == 1, 'Home shown (greeting "Device" $home); Workout tab "Your workout plan" $plan; returned Home');
        });
  });
}
