import 'package:flutter/material.dart';
import '../../models/plan.dart';
import '../../theme/app_theme.dart';
import '../posture_detection/posture_mode.dart';

/// One exercise as prescribed in the user's plan (Module 3).
class ExerciseDetail extends StatelessWidget {
  final PlannedExercise planned;
  final List<String> safetyNotes;

  const ExerciseDetail({Key? key, required this.planned, this.safetyNotes = const []}) : super(key: key);

  Widget _buildMetricMini(String val, String lbl) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(val, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primary)),
            const SizedBox(height: 2),
            Text(lbl, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildMuscleChip(String label) {
    return Container(
      margin: const EdgeInsets.only(right: 6, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.primary),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.primary)),
    );
  }

  Widget _buildTechniqueStep(String num, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(num, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: AppTheme.textPrimary, height: 1.4, fontSize: 14))),
        ],
      ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
      );

  @override
  Widget build(BuildContext context) {
    final e = planned.exercise;
    final levelColor = e.level == 1 ? AppTheme.success : (e.level == 2 ? AppTheme.warning : AppTheme.error);
    final minutes = (planned.totalSeconds / 60).ceil();

    final metrics = planned.timed
        ? [
            if (planned.sets > 1) _buildMetricMini('${planned.sets}', 'Sets'),
            _buildMetricMini(planned.seconds >= 120 ? '${(planned.seconds / 60).round()}m' : '${planned.seconds}s', planned.sets > 1 ? 'Per set' : 'Duration'),
            if (planned.restSeconds > 0) _buildMetricMini('${planned.restSeconds}s', 'Rest'),
            _buildMetricMini('${minutes}m', 'Total'),
          ]
        : [
            _buildMetricMini('${planned.sets}', 'Sets'),
            _buildMetricMini('${planned.reps}', 'Reps'),
            _buildMetricMini('${planned.restSeconds}s', 'Rest'),
            _buildMetricMini('${minutes}m', 'Duration'),
          ];

    return Scaffold(
      appBar: AppBar(title: Text(e.name, style: const TextStyle(fontSize: 16)), centerTitle: true),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.all(20),
                  height: 180,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF2C2C3E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  alignment: Alignment.center,
                  child: Text(e.icon, style: const TextStyle(fontSize: 80)),
                ),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: metrics)),
                if (e.compendium.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Text(
                      'Energy estimate: ${e.met} METs — 2024 Compendium of Physical Activities, code ${e.compendium.replaceAll('*', '')}'
                      '${e.compendium.endsWith('*') ? ' (closest listed activity)' : ''}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ),
                _heading('Muscle Groups'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(children: [for (final m in e.muscles) _buildMuscleChip(m)]),
                ),
                _heading('Difficulty'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(color: levelColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                        child: Text('⚡ ${e.levelLabel}', style: TextStyle(color: levelColor, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(20)),
                        child: Text(e.impact == 'low' ? 'Low impact' : 'High impact',
                            style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                if (planned.reasons.isNotEmpty || e.equipment != 'none')
                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (planned.reasons.isNotEmpty) ...[
                          const Text('Why this exercise for you', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primary)),
                          for (final r in planned.reasons)
                            Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $r', style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.35))),
                        ],
                        if (e.equipment != 'none')
                          Padding(
                            padding: EdgeInsets.only(top: planned.reasons.isNotEmpty ? 8 : 0),
                            child: Text('You will need: ${e.equipment}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                          ),
                      ],
                    ),
                  ),
                _heading('Technique'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    e.techniqueSource == 'free-exercise-db'
                        ? 'Muscles and technique adapted from the free-exercise-db open dataset (public domain): ${e.referenceId}'
                            '${e.referenceMatch == 'related' ? ' — closest match' : ''}. Cues are rewritten for the prescribed sets and safety.'
                        : 'Technique written by the Baymax team (no matching entry in an open dataset); pending professional review.',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      for (var i = 0; i < e.steps.length; i++) _buildTechniqueStep('${i + 1}', e.steps[i]),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('🛡️', style: TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          e.impact == 'low'
                              ? 'Selected as safe for your profile. Move with control and stop if you feel sharp pain, dizziness or chest discomfort.'
                              : 'High-impact move. Land softly, keep your core braced and stop if you feel sharp pain, dizziness or chest discomfort.',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [AppTheme.background, AppTheme.background.withOpacity(0.0)],
                ),
              ),
              child: ElevatedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PostureModeSelection())),
                child: const Text('Start Exercise →'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
