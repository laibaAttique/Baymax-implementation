import 'package:flutter/material.dart';
import 'dart:async';
import '../../theme/app_theme.dart';

class CameraDetection extends StatefulWidget {
  const CameraDetection({Key? key}) : super(key: key);

  @override
  _CameraDetectionState createState() => _CameraDetectionState();
}

class _CameraDetectionState extends State<CameraDetection> {
  int _reps = 5;
  String _feedbackMessage = '⚡ Keep your back straight';
  Timer? _repTimer;
  Timer? _feedbackTimer;

  final List<String> _feedbackMessages = [
    '⚡ Keep your back straight',
    '✅ Great form! Keep going',
    '⚡ Lower your hips more',
    '✅ Perfect depth!'
  ];
  int _msgIdx = 0;

  @override
  void initState() {
    super.initState();
    // Simulate reps counting
    _repTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_reps < 12 && mounted) {
        setState(() => _reps++);
      }
    });
    // Simulate feedback cycling
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

  Widget _buildDetectionChip(String text) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 4)],
      ),
      child: Row(
        children: [
          Container(
            width: 18, height: 18,
            decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.check, color: Colors.white, size: 12),
          ),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Baymax', style: TextStyle(fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Viewfinder
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              height: 340,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF0F0F1A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Stack(
                children: [
                  // Corner brackets (simulated with icons for simplicity, or containers)
                  Positioned(top: 16, left: 16, child: _buildCorner(true, true)),
                  Positioned(top: 16, right: 16, child: _buildCorner(true, false)),
                  Positioned(bottom: 16, left: 16, child: _buildCorner(false, true)),
                  Positioned(bottom: 16, right: 16, child: _buildCorner(false, false)),

                  // Reps Badge
                  Positioned(
                    top: 16, right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          const Text('REPS', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (Widget child, Animation<double> animation) => ScaleTransition(scale: animation, child: child),
                            child: Text('$_reps', key: ValueKey(_reps), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.primary, height: 1)),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Skeleton Placeholder
                  Center(
                    child: Opacity(
                      opacity: 0.6,
                      child: Image.network(
                        'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e4/Stick_Figure.svg/1024px-Stick_Figure.svg.png',
                        color: AppTheme.success,
                        height: 200,
                      ),
                    ),
                  ),

                  // Angle Badges
                  Positioned(left: 40, bottom: 60, child: _buildAngleBadge('90°')),
                  Positioned(right: 50, bottom: 60, child: _buildAngleBadge('88°')),

                  // Feedback Banner
                  Positioned(
                    bottom: 16, left: 16, right: 16,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        key: ValueKey(_feedbackMessage),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xEBE8651A), borderRadius: BorderRadius.circular(12)),
                        alignment: Alignment.center,
                        child: Text(_feedbackMessage, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Status Section
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Text('Align your body within the frame', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  SizedBox(height: 8),
                  Text('Camera Detection', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
                      SizedBox(width: 8),
                      Text('Detecting posture...', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w500, fontSize: 14)),
                    ],
                  ),
                ],
              ),
            ),

            // Detection Chips
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildDetectionChip('Landmarks detected'),
                  _buildDetectionChip('Angles calculated'),
                ],
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: ElevatedButton(
                onPressed: () {
                  // Navigate to Posture Feedback
                },
                child: const Text('Stop Session'),
              ),
            ),
            const Text('Processing is done locally. No video is stored.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildCorner(bool isTop, bool isLeft) {
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        border: Border(
          top: isTop ? const BorderSide(color: AppTheme.primary, width: 3) : BorderSide.none,
          bottom: !isTop ? const BorderSide(color: AppTheme.primary, width: 3) : BorderSide.none,
          left: isLeft ? const BorderSide(color: AppTheme.primary, width: 3) : BorderSide.none,
          right: !isLeft ? const BorderSide(color: AppTheme.primary, width: 3) : BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildAngleBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
    );
  }
}
