import 'package:flutter/material.dart';

import '../models/plan.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// Module 4: how this week compares with the training profile of the person's Module 2 classification.
class TrainingProfileCard extends StatelessWidget {
  final PlanProfileSummary summary;
  const TrainingProfileCard(this.summary, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return GlassCard(
      key: const ValueKey('training-profile'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const IconWell(icon: Icons.insights_rounded, color: AppTheme.primary, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Your training profile: ${s.category}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textPrimary)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(s.emphasis, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.45)),
          const SizedBox(height: 4),
          Text('Highest intensity scheduled: ${s.maxBand.label} (${s.maxBand.range})',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _row('Aerobic', '${s.aerobicMinutes} of ${s.aerobicTargetMin}–${s.aerobicTargetMax} min a week', s.aerobicMet),
          _row('Strength', '${s.strengthDays} of ${s.strengthTarget}+ days', s.strengthMet),
          _row('Stretching', '${s.flexibilityDays} of ${s.flexibilityTarget}+ days', s.flexibilityMet),
          for (final n in s.notes)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(n, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.45)),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Targets restate WHO 2020 and related guidelines; aerobic minutes count a vigorous minute as two. '
                'Pending professional review.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, bool met) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Icon(met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 16, color: met ? AppTheme.success : AppTheme.warning),
          const SizedBox(width: 8),
          SizedBox(width: 78, child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary))),
        ]),
      );
}
