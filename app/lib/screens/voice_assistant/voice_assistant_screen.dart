import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../theme/app_theme.dart';

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

  Widget _buildSuggestChip(String text) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.primary),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A), // Dark navy from mockup
      body: SafeArea(
        child: Stack(
          children: [
            // Close Button
            Positioned(
              top: 16, left: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ),
            ),

            // Center Content (Waveform & Mic)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Listening...', style: TextStyle(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 1)),
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
                      return Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
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
                        child: const Text('🎙️', style: TextStyle(fontSize: 32)),
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
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                decoration: const BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.volume_up, color: AppTheme.primary, size: 16),
                        SizedBox(width: 6),
                        Text('Baymax is responding', style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your next workout is a full-body HIIT session. It includes squats, push-ups, and planks. Shall I start the workout or adjust the intensity?',
                      style: TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildSuggestChip('Start workout'),
                          _buildSuggestChip('Lower intensity'),
                          _buildSuggestChip('Show exercises'),
                          _buildSuggestChip('Check my calories'),
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
