import 'package:flutter/material.dart';

import '../../models/plan.dart';
import '../../models/workout_session.dart';
import '../../services/exercise_library.dart';
import '../../services/posture/movement_patterns.dart';
import '../../theme/app_theme.dart';
import 'posture_mode.dart';

/// TEMPORARY screen for testing Modules 5 and 6 on their own.
///
/// The dashboard's "Posture Check" tile opens the mode selection, which needs
/// an exercise. Until the Workout Plan module passes one in, this list lets the
/// tester pick an exercise from the app's existing library. Sets, reps and
/// rest are the library defaults ([SessionExercise.fromExercise]), not a
/// personalised prescription.
///
/// To retire it: push `PostureModeSelection(request: …)` directly from the
/// workout plan and delete this file.
class ExercisePickerScreen extends StatefulWidget {
  const ExercisePickerScreen({super.key});

  @override
  State<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<ExercisePickerScreen> {
  late final Future<void> _loading = ExerciseLibrary.load();

  void _open(Exercise exercise) {
    final request = WorkoutSessionRequest(exercise: SessionExercise.fromExercise(exercise));
    Navigator.push(context, MaterialPageRoute(builder: (_) => PostureModeSelection(request: request)));
  }

  Widget _buildTile(Exercise e, {required bool camera}) {
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
          subtitle: Text(
            camera ? 'Camera Detection or Manual Guidance' : 'Manual Guidance only',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          trailing: Icon(camera ? Icons.videocam_outlined : Icons.list_alt, color: AppTheme.primary),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Posture Check', style: TextStyle(fontSize: 16)), centerTitle: true),
      body: FutureBuilder<void>(
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
          final all = ExerciseLibrary.all;
          bool tracked(Exercise e) => MovementPatterns.resolve(e.id, e.movement, e.noTrackingReason).supportsCameraTracking;
          final camera = [for (final e in all) if (tracked(e)) e];
          final manual = [for (final e in all) if (!tracked(e)) e];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(16)),
                child: const Text(
                  'Temporary test screen: choose an exercise to try posture detection. '
                  'This will be replaced by your workout plan.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.4),
                ),
              ),
              _heading('Camera posture detection'),
              for (final e in camera) _buildTile(e, camera: true),
              _heading('Manual guidance'),
              for (final e in manual) _buildTile(e, camera: false),
            ],
          );
        },
      ),
    );
  }
}
