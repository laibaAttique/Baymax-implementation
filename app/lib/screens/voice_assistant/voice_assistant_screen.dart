import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../../services/user_session.dart';
import '../diet/diet_tracker.dart';
import '../profile/profile_screen.dart';
import '../workout_and_exercise/workout_plan.dart';

class VoiceAssistantScreen extends StatefulWidget {
  const VoiceAssistantScreen({Key? key}) : super(key: key);

  @override
  _VoiceAssistantScreenState createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> with TickerProviderStateMixin {
  late AnimationController _micPulseController;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _micPulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _waveController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _micPulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  Widget _buildWaveBar(double delayOffset) {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        // Create a sine wave effect based on controller value and offset
        double t = (_waveController.value * 2 * math.pi) + delayOffset;
        double sinValue = math.sin(t);
        double height = 20 + 40 * ((1 + sinValue) / 2); // Ranges 20 to 60
        double opacity = 0.5 + 0.5 * ((1 + sinValue) / 2);
        
        return Container(
          width: 6,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(opacity),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      },
    );
  }

  Widget _buildSuggestChip(String text, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Pressable(
        radius: 24,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.8), borderRadius: BorderRadius.circular(24), border: Border.all(color: AppTheme.primary, width: 1.3)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(text, style: const TextStyle(color: AppTheme.primary, fontSize: 13.5, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }

  void _open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  /// An example answer built from the user's real plan (the voice assistant itself is not part of this version).
  String get _example {
    final plan = UserSession.instance.plan;
    final today = plan?.workoutFor(DateTime.now());
    if (plan == null) return 'Complete your health profile and I can tell you about today\'s workout.';
    if (today == null) return 'Today is a rest day in your plan. A relaxed walk and some stretching are all you need. Want to see your week?';
    return 'Today\'s workout is ${today.name}, about ${today.durationMin} minutes. Shall I open it, or look at your calories?';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Close Button
            Positioned(
              top: 16, left: 16,
              child: Pressable(
                radius: 24,
                semanticLabel: 'Close',
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 48, height: 48,
                  decoration: AppTheme.glass(radius: 24),
                  alignment: Alignment.center,
                  child: const Icon(Icons.close_rounded, color: AppTheme.textPrimary, size: 22),
                ),
              ),
            ),

            // Center Content (Waveform & Mic)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Voice assistant preview', style: TextStyle(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text('Speaking and listening are not available in this version. Tap a suggestion to continue.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4)),
                  ),
                  const SizedBox(height: 32),
                  
                  // Waveform
                  SizedBox(
                    height: 80,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildWaveBar(0),
                        _buildWaveBar(1),
                        _buildWaveBar(2),
                        _buildWaveBar(3),
                        _buildWaveBar(4),
                        _buildWaveBar(3),
                        _buildWaveBar(2),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Pulsing Mic
                  AnimatedBuilder(
                    animation: _micPulseController,
                    builder: (context, child) {
                      return Pressable(
                        radius: 40,
                        semanticLabel: 'Microphone (not available in this version)',
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Listening is not available in this version. Tap a suggestion below.'))),
                        child: Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          gradient: AppTheme.buttonGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withOpacity(0.4 * (1 - _micPulseController.value)),
                              spreadRadius: 20 * _micPulseController.value,
                              blurRadius: 10 * _micPulseController.value,
                            )
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.mic_rounded, color: Colors.white, size: 34),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 120), // Spacing for bottom sheet
                ],
              ),
            ),

            // Response Card
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                decoration: BoxDecoration(
                  color: const Color(0xF0F6F7FF),
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
                  border: Border.all(color: Colors.white, width: 1.2),
                  boxShadow: AppTheme.glowShadow(blur: 30, opacity: 0.35, offset: const Offset(0, -6)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.volume_up_rounded, color: AppTheme.primary, size: 18),
                        SizedBox(width: 6),
                        Text('Example answer', style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _example,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildSuggestChip('Open my workout', () => _open(const WorkoutPlan())),
                          _buildSuggestChip('Lower intensity', () {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: const Text('Your intensity follows your health profile. Update your details to change it.'),
                              action: SnackBarAction(label: 'Open profile', onPressed: () => _open(const ProfileScreen())),
                            ));
                          }),
                          _buildSuggestChip('Check my calories', () => _open(const DietTracker())),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
