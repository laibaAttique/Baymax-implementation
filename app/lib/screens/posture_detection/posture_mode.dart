import 'package:flutter/material.dart';

import '../../models/workout_session.dart';
import '../../services/app_permissions.dart';
import '../../services/posture/movement_patterns.dart';
import '../../theme/app_theme.dart';
import '../../widgets/notification_bell.dart';
import 'camera_detection.dart';
import 'manual_guidance.dart';
import 'widgets/safety_notes_card.dart';

/// S-12: choose Camera Detection or Manual Guidance for one exercise.
///
/// INTEGRATION POINT (Workout Plan module): this is the entry to Modules 5/6.
/// Push it with a [WorkoutSessionRequest] for the selected exercise.
class PostureModeSelection extends StatefulWidget {
  final WorkoutSessionRequest request;
  const PostureModeSelection({super.key, required this.request});

  @override
  State<PostureModeSelection> createState() => _PostureModeSelectionState();
}

class _PostureModeSelectionState extends State<PostureModeSelection> {
  // Camera tracking follows the exercise's movement pattern; full form scoring only where the rules were tested.
  late final ExercisePostureConfig _support = MovementPatterns.forSession(widget.request.exercise);
  late final bool _cameraSupported = _support.supportsCameraTracking;
  late SessionMode _selectedMode = _cameraSupported ? SessionMode.camera : SessionMode.manual;

  // Consent is off until the user gives it (report FR15.3).
  bool _cameraConsent = false;
  bool _requesting = false;

  Future<void> _continue() async {
    if (_selectedMode == SessionMode.manual) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ManualGuidance(request: widget.request)));
      return;
    }
    if (!_cameraConsent) {
      _showMessage('Turn on "I agree to enable camera access" to use Camera Detection, or choose Manual Guidance.');
      return;
    }
    setState(() => _requesting = true);
    final outcome = await AppPermissions.instance.requestCamera();
    if (!mounted) return;
    setState(() => _requesting = false);
    if (outcome == PermissionOutcome.granted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CameraDetection(request: widget.request)));
    } else {
      await _showPermissionDenied(outcome == PermissionOutcome.permanentlyDenied);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _showPermissionDenied(bool permanently) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Camera access needed'),
        content: Text(
          permanently
              ? 'Camera access is turned off for Baymax. You can enable it in Settings, or continue with Manual Guidance, which does not use the camera.'
              : 'Camera Detection cannot start without camera permission. You can continue with Manual Guidance, which does not use the camera.',
        ),
        actions: [
          if (permanently)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                AppPermissions.instance.openSettings();
              },
              child: const Text('Open Settings'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              setState(() => _selectedMode = SessionMode.manual);
            },
            child: const Text('Use Manual Guidance'),
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard(SessionMode mode, String icon, String title, String desc, {bool enabled = true}) {
    final isSelected = _selectedMode == mode;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        onTap: enabled ? () => setState(() => _selectedMode = mode) : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border, width: 2),
            boxShadow: isSelected
                ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 4))]
                : null,
          ),
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryLight : AppTheme.background,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(icon, style: const TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                          const SizedBox(height: 4),
                          Text(desc, style: const TextStyle(color: AppTheme.textSecondary, height: 1.4, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (isSelected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const Icon(Icons.check, color: Colors.white, size: 16),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _cameraDescription(String name) => switch (_support.level) {
        CameraSupportLevel.validatedForm ||
        CameraSupportLevel.experimentalForm =>
          'Track posture using live camera for real-time adjustments and analysis.',
        CameraSupportLevel.basicTracking => _support.supportsHoldTiming
            ? 'Basic tracking: times your hold while the camera sees you in position. Form is not scored for this exercise.'
            : 'Basic tracking: counts your repetitions from your ${_support.movementPattern.measures} with the live camera. '
                'Form is not scored for this exercise.',
        CameraSupportLevel.notSupported => 'Camera tracking is not available for $name: ${_support.unsupportedReason} Use Manual Guidance.',
      };

  @override
  Widget build(BuildContext context) {
    final exercise = widget.request.exercise;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Mode', style: TextStyle(fontSize: 16)),
        centerTitle: true,
        actions: const [NotificationBell(), SizedBox(width: 8)],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Text(exercise.icon, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${exercise.name} · ${exercise.targetLabel}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            SafetyNotesCard(exercise.safetyNotes),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Column(
                children: [
                  _buildModeCard(
                    SessionMode.camera,
                    '📷',
                    'Camera Detection',
                    _cameraDescription(exercise.name),
                    enabled: _cameraSupported,
                  ),
                  _buildModeCard(
                    SessionMode.manual,
                    '🏃',
                    'Manual Guidance',
                    'Follow guided exercises with visual cues without active camera tracking.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    const Text('ℹ️', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RichText(
                        text: const TextSpan(
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                          children: [
                            TextSpan(text: 'Camera data is processed '),
                            TextSpan(
                                text: 'locally on your device',
                                style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                            TextSpan(text: ' and never stored or sent to our servers.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'I agree to enable camera access',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _cameraSupported ? AppTheme.textPrimary : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  Switch(
                    key: const Key('cameraConsent'),
                    value: _cameraConsent,
                    onChanged: _cameraSupported ? (val) => setState(() => _cameraConsent = val) : null,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: ElevatedButton(
                onPressed: _requesting ? null : _continue,
                child: const Text('Continue'),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Skip for now', style: TextStyle(color: AppTheme.textSecondary)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
