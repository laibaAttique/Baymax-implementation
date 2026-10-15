import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../../widgets/progress_ring.dart';
import '../dashboard/main_navigation.dart';
import 'session_queue.dart';

/// The summary after a guided session. It reports only what the app observed: exercises finished, skipped, sets ticked off and
/// elapsed time. There is no posture score or form feedback because no camera model is connected in this version.
class PostureFeedbackScreen extends StatelessWidget {
  final SessionResult result;
  const PostureFeedbackScreen({Key? key, required this.result}) : super(key: key);

  String _duration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _stat(IconData icon, String val, String lbl) => Expanded(
        child: Column(
          children: [
            Icon(icon, size: 20, color: AppTheme.primary),
            const SizedBox(height: 6),
            Text(val, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.4)),
            Text(lbl, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final frac = result.total == 0 ? 0.0 : result.completed / result.total;
    return Scaffold(
      appBar: AppBar(title: const Text('Session summary'), automaticallyImplyLeading: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Reveal(
              child: Column(children: [
                const Text('Session complete', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.7)),
                const SizedBox(height: 4),
                Text(result.skipped == 0 ? 'You finished every exercise.' : 'Every exercise counts, including the ones you skipped for today.',
                    textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14.5, fontWeight: FontWeight.w500, height: 1.4)),
              ]),
            ),
            const SizedBox(height: 26),
            Reveal(
              index: 1,
              child: ProgressRing(
                size: 164,
                stroke: 14,
                value: frac,
                semanticLabel: '${result.completed} of ${result.total} exercises completed',
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${result.completed}/${result.total}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -1, height: 1.05)),
                  const Text('exercises', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
                ]),
              ),
            ),
            const SizedBox(height: 26),
            Reveal(
              index: 2,
              child: GlassCard(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Row(children: [
                  _stat(Icons.timer_rounded, _duration(result.elapsed), 'Time'),
                  Container(width: 1, height: 44, color: AppTheme.border),
                  _stat(Icons.layers_rounded, '${result.setsDone}', 'Sets ticked'),
                  Container(width: 1, height: 44, color: AppTheme.border),
                  _stat(Icons.skip_next_rounded, '${result.skipped}', 'Skipped'),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            const Reveal(
              index: 3,
              child: GlassCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconWell(icon: Icons.info_outline_rounded, color: AppTheme.macroFat, size: 38),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Posture scoring and injury-risk updates need camera analysis, which is not part of this version. Remember to mark today\'s workout as completed on the Workout tab.',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.45, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 26),
            GlowButton(
              icon: Icons.fitness_center_rounded,
              label: 'Back to workout plan',
              onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainNavigation(initialIndex: 2)), (route) => false),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainNavigation(initialIndex: 3)), (route) => false),
              child: const Text('View analytics'),
            ),
          ],
        ),
      ),
    );
  }
}
