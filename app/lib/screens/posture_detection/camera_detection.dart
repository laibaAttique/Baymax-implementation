import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/plan.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import 'manual_guidance.dart';

/// A PREVIEW of live posture detection. No camera feed or pose model is connected in this version, so the skeleton, rep count,
/// angles and feedback below are simulated to show the intended layout. This is stated on the screen.
class CameraDetection extends StatefulWidget {
  final List<PlannedExercise> queue;
  final int startIndex;
  const CameraDetection({Key? key, this.queue = const [], this.startIndex = 0}) : super(key: key);

  @override
  State<CameraDetection> createState() => _CameraDetectionState();
}

class _CameraDetectionState extends State<CameraDetection> {
  int _reps = 5;
  String _feedbackMessage = 'Keep your back straight';
  Timer? _repTimer;
  Timer? _feedbackTimer;

  final List<String> _feedbackMessages = ['Keep your back straight', 'Great form, keep going', 'Lower your hips more', 'Perfect depth'];
  int _msgIdx = 0;

  @override
  void initState() {
    super.initState();
    _repTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_reps < 12 && mounted) setState(() => _reps++);
    });
    _feedbackTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        setState(() {
          _msgIdx = (_msgIdx + 1) % _feedbackMessages.length;
          _feedbackMessage = _feedbackMessages[_msgIdx];
        });
      }
    });
  }

  @override
  void dispose() {
    _repTimer?.cancel();
    _feedbackTimer?.cancel();
    super.dispose();
  }

  Widget _corner(bool isTop, bool isLeft) {
    const side = BorderSide(color: Colors.white, width: 3);
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isTop && isLeft ? 10 : 0),
          topRight: Radius.circular(isTop && !isLeft ? 10 : 0),
          bottomLeft: Radius.circular(!isTop && isLeft ? 10 : 0),
          bottomRight: Radius.circular(!isTop && !isLeft ? 10 : 0),
        ),
        border: Border(
          top: isTop ? side : BorderSide.none,
          bottom: !isTop ? side : BorderSide.none,
          left: isLeft ? side : BorderSide.none,
          right: !isLeft ? side : BorderSide.none,
        ),
      ),
    );
  }

  Widget _angleBadge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.92), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
      );

  void _openManual() {
    final queue = widget.queue;
    if (queue.isEmpty) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ManualGuidance(queue: queue, startIndex: widget.startIndex)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Camera detection')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          children: [
            GlassCard(
              tint: AppTheme.tint(AppTheme.warning, 0.16),
              padding: const EdgeInsets.all(14),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.science_rounded, color: AppTheme.warning),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Preview only. Live camera analysis is not part of this version, so the skeleton, rep count, angles and feedback are simulated.',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 13.5, height: 1.45, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 340,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1B1F3B), Color(0xFF0E1128)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(AppTheme.rHero),
                boxShadow: AppTheme.glowShadow(blur: 30, opacity: 0.28, offset: const Offset(0, 14)),
              ),
              child: Stack(
                children: [
                  Positioned(top: 16, left: 16, child: _corner(true, true)),
                  Positioned(bottom: 16, left: 16, child: _corner(false, true)),
                  Positioned(bottom: 16, right: 16, child: _corner(false, false)),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: [
                          const Text('REPS (SIMULATED)', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppTheme.textSecondary)),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                            child: Text('$_reps', key: ValueKey(_reps), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppTheme.primary, height: 1.1)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Center(child: Icon(Icons.accessibility_new_rounded, size: 200, color: Color(0xFF8E96FF))),
                  Positioned(left: 40, bottom: 76, child: _angleBadge('90°')),
                  Positioned(right: 50, bottom: 76, child: _angleBadge('88°')),
                  Positioned(
                    bottom: 16,
                    left: 56,
                    right: 56,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        key: ValueKey(_feedbackMessage),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(14)),
                        alignment: Alignment.center,
                        child: Text(_feedbackMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text('Camera detection', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.4)),
            const SizedBox(height: 4),
            const Text('Align your body within the frame', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 22),
            GlowButton(icon: Icons.self_improvement_rounded, label: 'Use manual guidance', onPressed: _openManual),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Stop preview')),
          ],
        ),
      ),
    );
  }
}
