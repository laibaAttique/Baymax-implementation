import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// TEMPORARY: lets you confirm which copy of the project is running.
/// If you can open this screen, you are running the "baymaxxxx 2" copy that
/// Claude edited. Delete this file (and the long-press in splash_screen.dart)
/// once you have confirmed.
class TestScreen extends StatelessWidget {
  const TestScreen({Key? key}) : super(key: key);

  static const marker = 'BAYMAX-COPY-2-OK';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('✅', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              const Text(
                'You are running the edited copy',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Folder: Downloads/baymaxxxx 2/untitled folder/app',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(12)),
                child: const Text(marker, style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary, letterSpacing: 1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
