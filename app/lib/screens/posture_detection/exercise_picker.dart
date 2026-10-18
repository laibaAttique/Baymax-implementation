import 'package:flutter/material.dart';

import '../../models/plan.dart';
import '../../models/workout_session.dart';
import '../../services/exercise_library.dart';
import '../../services/posture/movement_patterns.dart';
import '../../theme/app_theme.dart';
import 'posture_mode.dart';

/// The generic exercise library (Module 5): any curated exercise, outside the personalised plan. Sets, reps and rest
/// are the library defaults ([SessionExercise.fromExercise]), not a prescription, and sessions started here are saved
/// as independent workouts (no plan link). Shown as the "Exercise library" tab of `PostureDetectionHome` and on its own.
class ExercisePickerScreen extends StatelessWidget {
  const ExercisePickerScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Exercise library', style: TextStyle(fontSize: 16)), centerTitle: true),
        body: const ExerciseLibraryList(),
      );
}

class ExerciseLibraryList extends StatefulWidget {
  const ExerciseLibraryList({super.key});

  @override
  State<ExerciseLibraryList> createState() => _ExerciseLibraryListState();
}

class _ExerciseLibraryListState extends State<ExerciseLibraryList> {
  late final Future<void> _loading = ExerciseLibrary.load();

  void _open(Exercise exercise) {
    final request = WorkoutSessionRequest(exercise: SessionExercise.fromExercise(exercise));
    Navigator.push(context, MaterialPageRoute(builder: (_) => PostureModeSelection(request: request)));
  }

  static String capabilityLabel(ExercisePostureConfig c) => switch (c.level) {
        CameraSupportLevel.validatedForm || CameraSupportLevel.experimentalForm => 'Camera: posture score and corrections',
        CameraSupportLevel.basicTracking => c.supportsHoldTiming ? 'Camera: hold timer' : 'Camera: rep counting',
        CameraSupportLevel.notSupported => 'Manual Guidance only',
      };

  Widget _buildTile(Exercise e, ExercisePostureConfig c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => _open(e),
          leading: Text(e.icon, style: const TextStyle(fontSize: 28)),
          title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          subtitle: Text(capabilityLabel(c), style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          trailing: Icon(c.supportsCameraTracking ? Icons.videocam_outlined : Icons.list_alt, color: AppTheme.primary),
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !ExerciseLibrary.isLoaded) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('The exercise library could not be loaded.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary)),
            ),
          );
        }
        final all = [for (final e in ExerciseLibrary.all) (e, MovementPatterns.resolve(e.id, e.movement, e.noTrackingReason))];
        final camera = [for (final x in all) if (x.$2.supportsCameraTracking) x];
        final manual = [for (final x in all) if (!x.$2.supportsCameraTracking) x];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(16)),
              child: const Text(
                'General exercises with default sets and reps, not your personalised plan. '
                'Sessions you do here are saved as separate workouts.',
                style: TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.4),
              ),
            ),
            _heading('Camera posture detection'),
            for (final (e, c) in camera) _buildTile(e, c),
            _heading('Manual guidance'),
            for (final (e, c) in manual) _buildTile(e, c),
          ],
        );
      },
    );
  }
}
