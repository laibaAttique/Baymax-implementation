// Controlled test data for the real-device integration tests.
//
// The device tests never sign in and never initialise Firebase, so nothing they do can read or change a real account:
// the profile below lives only in memory, finished sessions go to [MemoryWorkoutLog], and every cloud call the app makes
// fails closed exactly as it does when the phone is offline.
import 'package:app/models/health_profile.dart';
import 'package:app/models/workout_session.dart';
import 'package:app/services/app_permissions.dart';
import 'package:app/services/workout_session/workout_log_service.dart';
import 'package:permission_handler/permission_handler.dart';

/// The fictional test user. Healthy, no conditions, [frequency] training days a week.
HealthProfile testProfile({int frequency = 6, List<String> conditions = const []}) => HealthProfile(
      fullName: 'Device Tester',
      dob: '1998-05-20',
      gender: 'Female',
      heightValue: 165,
      weightValue: 60,
      medicalConditions: conditions,
      primaryGoal: 'Maintain & Stay Fit',
      activityLevel: 'Moderately Active',
      workoutFrequency: frequency,
    );

/// In-memory session store: sessions finished during a test are kept here, never uploaded.
class MemoryWorkoutLog implements WorkoutLogStore {
  final List<SessionSummary> saved = [];
  final List<String> flagged = [];

  @override
  Future<void> save(SessionSummary summary) async => saved.add(summary);

  @override
  Future<void> markTooDifficult(String exerciseId) async => flagged.add(exerciseId);

  @override
  Future<Set<String>> tooDifficultExercises() async => flagged.toSet();

  @override
  Future<List<WorkoutLogEntry>> recent({int limit = 20}) async => const [];

  @override
  Future<List<WorkoutLogEntry>> since(DateTime from) async => [
        for (var i = 0; i < saved.length; i++)
          if (!saved[i].endedAt.isBefore(from))
            WorkoutLogEntry.fromJson('s$i', Map<String, dynamic>.from(WorkoutLog.toJson(saved[i]))),
      ];
}

/// Reports the phone's REAL permission state but never shows the Android permission dialog (a Flutter test cannot
/// answer a native dialog, and the tests must not change the phone's permissions). Granted → the real camera /
/// microphone path runs; not granted → the app's own "access needed" path runs.
class DevicePermissions extends AppPermissions {
  const DevicePermissions();

  static final Map<String, String> observed = {};

  @override
  Future<PermissionOutcome> requestCamera() => _status('camera', Permission.camera);

  @override
  Future<PermissionOutcome> requestMicrophone() => _status('microphone', Permission.microphone);

  @override
  Future<bool> openSettings() async => false;

  Future<PermissionOutcome> _status(String name, Permission p) async {
    final s = await p.status;
    observed[name] = s.name;
    if (s.isGranted || s.isLimited) return PermissionOutcome.granted;
    if (s.isPermanentlyDenied || s.isRestricted) return PermissionOutcome.permanentlyDenied;
    return PermissionOutcome.denied;
  }

  static Future<String> statusOf(Permission p) async => (await p.status).name;
}
