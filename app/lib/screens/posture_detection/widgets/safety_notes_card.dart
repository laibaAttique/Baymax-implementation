import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// The Module 4 safety adaptations for this exercise, shown before and during a Module 5 session. Nothing when empty.
class SafetyNotesCard extends StatelessWidget {
  final List<String> notes;
  final EdgeInsetsGeometry margin;
  const SafetyNotesCard(this.notes, {super.key, this.margin = const EdgeInsets.fromLTRB(20, 12, 20, 0)});

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('safety-notes'),
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.rMedium),
        border: Border.all(color: AppTheme.teal.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.health_and_safety_rounded, size: 18, color: AppTheme.teal),
            SizedBox(width: 8),
            Text('Adapted for you', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          ]),
          const SizedBox(height: 6),
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $n', style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.textSecondary)),
            ),
        ],
      ),
    );
  }
}
