// Starts the real Baymax UI on the phone with a controlled, in-memory test session, and records every device case.
//
// What is real: the installed app binary, its widgets, theme and navigation shell (MainNavigation, the screen a signed-in
// user lands on), bundled datasets, plan generation, the camera plugin, MediaPipe, speech recognition and text-to-speech
// plugins, and every tap/scroll (dispatched through Flutter's gesture system by IntegrationTestWidgetsFlutterBinding,
// so no Android input injection is needed).
// What is controlled: the user (a fictional profile in memory instead of signing in), session storage (MemoryWorkoutLog),
// and permission prompts (DevicePermissions reports the phone's real permission state without showing a dialog).
// Firebase is initialised (the shell needs it) but nobody is signed in, so the database rules deny every read and write of
// user data; if an account is signed in on the build, every case stops as Blocked instead of using it.
import 'dart:convert';
import 'dart:io';

import 'package:app/firebase_options.dart';
import 'package:app/main.dart' show baymaxShell;
import 'package:app/models/health_profile.dart';
import 'package:app/models/workout_readiness.dart';
import 'package:app/screens/dashboard/main_navigation.dart';
import 'package:app/services/app_permissions.dart';
import 'package:app/services/realtime_db.dart';
import 'package:app/services/user_session.dart';
import 'package:app/services/workout_session/plan_progress.dart';
import 'package:app/services/workout_session/workout_session_controller.dart';
import 'package:app/theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'test_fixtures.dart';

final IntegrationTestWidgetsFlutterBinding binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

/// The in-memory store finished sessions go to during the current test.
late MemoryWorkoutLog sessionLog;

/// Thrown when a precondition outside the app is not met; the case is reported as Blocked, never as passed.
class Blocked implements Exception {
  final String reason;
  const Blocked(this.reason);
  @override
  String toString() => 'Blocked: $reason';
}

bool _firebaseReady = false;

/// The app shell needs Firebase initialised (e.g. the Profile tab builds AuthService). The tests initialise it but never
/// sign in. If a real account is signed in on this build, the tests refuse to run rather than act on that account.
Future<void> _ensureFirebaseWithoutAccount() async {
  if (!_firebaseReady) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }
    RealtimeDb.init();
    _firebaseReady = true;
  }
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    throw const Blocked('an account is signed in on this build of the app; the device tests do not run against real accounts');
  }
}

/// Resets all shared state and signs the fictional [profile] into the in-memory session (no account, nothing uploaded).
Future<void> startControlledSession(WidgetTester t, {HealthProfile? profile, WorkoutReadiness readiness = const WorkoutReadiness(clearance: true)}) async {
  await _ensureFirebaseWithoutAccount();
  AppPermissions.instance = const DevicePermissions();
  final session = WorkoutSessionController.instance;
  session.abandon();
  sessionLog = MemoryWorkoutLog();
  session.store = sessionLog;
  PlanProgress.instance.reset();
  UserSession.instance.loading = false;
  UserSession.instance.readiness = readiness;
  await UserSession.instance.setProfile(profile ?? testProfile());
}

/// Shows the app's signed-in shell (the same MaterialApp setup and MainNavigation as lib/main.dart after login).
Future<void> launchApp(WidgetTester t, {int tab = 0}) async {
  await t.pumpWidget(MaterialApp(
    title: 'Baymax',
    theme: AppTheme.lightTheme,
    builder: baymaxShell,
    home: MainNavigation(initialIndex: tab),
    debugShowCheckedModeBanner: false,
  ));
  await t.pump(const Duration(milliseconds: 500));
}

/// The outcome of one device case.
class Outcome {
  final bool ok;
  final String actual;
  const Outcome(this.ok, this.actual);
}

final List<Map<String, Object?>> _records = [];

Future<String> _shot(WidgetTester t, String id) async {
  try {
    // The conversion is reverted in each test's tear-down, so it is needed once per test (not once per run).
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage().timeout(const Duration(seconds: 10));
    }
    await t.pump(const Duration(milliseconds: 100)); // Android needs a frame after the surface conversion
    await binding.takeScreenshot(id).timeout(const Duration(seconds: 15));
    return '$id.png';
  } catch (e) {
    // Screenshots are evidence only; a failed capture never changes a result.
    return 'not captured (${e.runtimeType})';
  }
}

/// Progress line in the device log (flutter drive output), so every step is traceable.
void step(String text) => debugPrint('[device-step] $text');

/// One documented real-device case. [body] performs the steps and returns what it observed.
void deviceCase(
  String id, {
  required String req,
  required String objective,
  required String input,
  required String expected,
  required String file,
  required Future<Outcome> Function(WidgetTester t) body,
  Duration timeout = const Duration(minutes: 4),
}) {
  testWidgets('$id $objective', (t) async {
    final started = DateTime.now();
    Outcome o;
    var blocked = false;
    step('$id start');
    try {
      o = await body(t).timeout(timeout - const Duration(seconds: 40));
    } on Blocked catch (e) {
      blocked = true;
      o = Outcome(false, e.toString());
    } catch (e) {
      o = Outcome(false, 'Error: ${e.toString().split('\n').first}');
    }
    step('$id ${o.ok ? 'passed' : 'failed'}: ${o.actual}');
    final shot = await _shot(t, id);
    _records.add({
      'id': id,
      'req': req,
      'objective': objective,
      'input': input,
      'expected': expected,
      'actual': o.actual,
      'status': o.ok ? 'Passed' : (blocked ? 'Blocked' : 'Failed'),
      'file': 'integration_test/$file',
      'test': '$id $objective',
      'started': started.toIso8601String(),
      'durationMs': DateTime.now().difference(started).inMilliseconds,
      'screenshot': shot,
      'tool': 'Flutter integration_test (IntegrationTestWidgetsFlutterBinding), real device',
    });
    final data = binding.reportData ?? <String, dynamic>{};
    data['cases'] = _records;
    data['permissions'] = DevicePermissions.observed;
    data['os'] = Platform.operatingSystemVersion;
    binding.reportData = data;
    debugPrint('[device-case] ${jsonEncode(_records.last)}');
    // Leave a clean tree for the next case; camera and timers are disposed with their screens.
    WorkoutSessionController.instance.abandon();
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(milliseconds: 300));
    expect(o.ok, isTrue, reason: o.actual);
  }, timeout: Timeout(timeout));
}

String describe(Object? v) => v is String ? v : jsonEncode(v);

/// Camera cases need the phone's camera permission for the installed test build. The tests never grant permissions;
/// without it the case is Blocked (not failed, not passed).
Future<void> requireCameraPermission() async {
  final s = await DevicePermissions.statusOf(Permission.camera);
  if (s != 'granted') {
    throw Blocked('camera permission for the installed test build is "$s" on the phone (a reinstall resets it); '
        'the tests do not grant permissions. Allow Camera for Baymax in Android Settings and rerun');
  }
}
