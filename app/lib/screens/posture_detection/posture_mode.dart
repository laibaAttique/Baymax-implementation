import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'camera_detection.dart';

class PostureModeSelection extends StatefulWidget {
  const PostureModeSelection({Key? key}) : super(key: key);

  @override
  _PostureModeSelectionState createState() => _PostureModeSelectionState();
}

class _PostureModeSelectionState extends State<PostureModeSelection> {
  String _selectedMode = 'camera';
  bool _cameraEnabled = true;

  Widget _buildModeCard(String id, String icon, String title, String desc) {
    bool isSelected = _selectedMode == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedMode = id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border, width: 2),
          boxShadow: isSelected ? [BoxShadow(color: AppTheme.primary.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 4))] : null,
        ),
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryLight : AppTheme.background,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(icon, style: const TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(height: 4),
                      Text(desc, style: const TextStyle(color: AppTheme.textSecondary, height: 1.4, fontSize: 13)),
                    ],
                  ),
                )
              ],
            ),
            if (isSelected)
              Positioned(
                top: 0, right: 0,
                child: Container(
                  width: 26, height: 26,
                  decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const Icon(Icons.check, color: Colors.white, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Mode', style: TextStyle(fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.notifications_none), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Mode Cards
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildModeCard('camera', '📷', 'Camera Detection', 'Track posture using live camera for real-time adjustments and analysis.'),
                  _buildModeCard('manual', '🏃', 'Manual Guidance', 'Follow guided exercises with visual cues without active camera tracking.'),
                ],
              ),
            ),

            // Privacy Banner
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
                            TextSpan(text: 'locally on your device', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                            TextSpan(text: ' and never stored or sent to our servers.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Camera Access Toggle
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Expanded(child: Text('I agree to enable camera access', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary))),
                  Switch(
                    value: _cameraEnabled,
                    onChanged: (val) => setState(() => _cameraEnabled = val),
                    activeColor: AppTheme.primary,
                  ),
                ],
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: ElevatedButton(
                onPressed: () {
                  if (_selectedMode == 'camera') {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraDetection()));
                  } else {
                    // Manual Guidance
                  }
                },
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
