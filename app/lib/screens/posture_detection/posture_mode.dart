import 'package:flutter/material.dart';
import '../../models/plan.dart';
import '../../theme/app_theme.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/glass.dart';
import 'camera_detection.dart';
import 'manual_guidance.dart';
import 'session_queue.dart';

/// Choose how to be guided through a session: live camera (preview only in this version) or manual guidance.
class PostureModeSelection extends StatefulWidget {
  /// The exercises to walk through; empty means today's workout.
  final List<PlannedExercise> queue;
  final int startIndex;
  const PostureModeSelection({Key? key, this.queue = const [], this.startIndex = 0}) : super(key: key);

  @override
  State<PostureModeSelection> createState() => _PostureModeSelectionState();
}

class _PostureModeSelectionState extends State<PostureModeSelection> {
  String _selectedMode = 'manual';
  bool _cameraEnabled = false;

  Widget _buildModeCard(String id, IconData icon, String title, String desc, {String? badge}) {
    final isSelected = _selectedMode == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Semantics(
        selected: isSelected,
        button: true,
        label: title,
        excludeSemantics: true,
        child: Pressable(
          radius: AppTheme.rLarge,
          onTap: () => setState(() => _selectedMode = id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white.withOpacity(0.92) : AppTheme.card,
              borderRadius: BorderRadius.circular(AppTheme.rLarge),
              border: Border.all(color: isSelected ? AppTheme.primary : Colors.white, width: isSelected ? 2 : 1.2),
              boxShadow: isSelected ? AppTheme.glowShadow(blur: 26, opacity: 0.22, offset: const Offset(0, 10)) : AppTheme.softShadow(),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconWell(icon: icon, size: 50, filled: isSelected),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.3))),
                        if (badge != null) ...[const SizedBox(width: 8), InfoChip(badge, color: AppTheme.warning)],
                      ]),
                      const SizedBox(height: 4),
                      Text(desc, style: const TextStyle(color: AppTheme.textSecondary, height: 1.4, fontSize: 13.5, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      key: ValueKey(isSelected), color: isSelected ? AppTheme.primary : AppTheme.border),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _continue() {
    final queue = widget.queue.isNotEmpty ? widget.queue : defaultSessionQueue();
    final start = widget.queue.isNotEmpty ? widget.startIndex : 0;
    if (_selectedMode == 'camera') {
      if (!_cameraEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turn on camera access below to preview camera detection.')));
        return;
      }
      Navigator.push(context, MaterialPageRoute(builder: (_) => CameraDetection(queue: queue, startIndex: start)));
    } else {
      if (queue.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('There is no workout to guide you through yet. Complete your health profile first.')));
        return;
      }
      Navigator.push(context, MaterialPageRoute(builder: (_) => ManualGuidance(queue: queue, startIndex: start)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose guidance'),
        actions: [
          const NotificationBell(),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How would you like to be guided?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.7, height: 1.2)),
            const SizedBox(height: 18),
            Reveal(child: _buildModeCard('manual', Icons.self_improvement_rounded, 'Manual guidance', 'Step-by-step cues, a timer and set counter for each exercise in your plan.')),
            Reveal(
              index: 1,
              child: _buildModeCard('camera', Icons.videocam_rounded, 'Camera detection', 'Real-time posture tracking with your camera. A preview only in this version.', badge: 'Preview'),
            ),
            Reveal(
              index: 2,
              child: GlassCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const IconWell(icon: Icons.lock_rounded, color: AppTheme.teal, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text.rich(
                        const TextSpan(
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.45, fontWeight: FontWeight.w500),
                          children: [
                            TextSpan(text: 'When camera analysis is available, video will be processed '),
                            TextSpan(text: 'locally on your device', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                            TextSpan(text: ' and never stored or sent to our servers.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_selectedMode == 'camera')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text('Enable camera access', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                  value: _cameraEnabled,
                  onChanged: (val) => setState(() => _cameraEnabled = val),
                ),
              ),
            const SizedBox(height: 18),
            GlowButton(icon: Icons.arrow_forward_rounded, label: 'Continue', onPressed: _continue),
            Center(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Skip for now', style: TextStyle(color: AppTheme.textSecondary)))),
          ],
        ),
      ),
    );
  }
}
