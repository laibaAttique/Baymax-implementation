import 'package:flutter/material.dart';
import '../../models/plan.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../posture_detection/posture_mode.dart';

/// One exercise as prescribed in the user's plan (Module 3).
class ExerciseDetail extends StatelessWidget {
  final PlannedExercise planned;
  final List<String> safetyNotes;

  /// The whole session this exercise belongs to; guidance walks through it from [planned] onward.
  final List<PlannedExercise> queue;

  const ExerciseDetail({Key? key, required this.planned, this.safetyNotes = const [], this.queue = const []}) : super(key: key);

  Widget _buildMetricMini(String val, String lbl) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(val, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.4)),
          ),
          const SizedBox(height: 2),
          Text(lbl, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildTechniqueStep(String num, String text, int index) {
    return Reveal(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlassCard(
          radius: AppTheme.rMedium,
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(gradient: AppTheme.buttonGradient, shape: BoxShape.circle, boxShadow: AppTheme.glowShadow(blur: 10, opacity: 0.28, offset: const Offset(0, 3))),
                alignment: Alignment.center,
                child: Text(num, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, style: const TextStyle(color: AppTheme.textPrimary, height: 1.45, fontSize: 14.5, fontWeight: FontWeight.w500)))),
            ],
          ),
        ),
      ),
    );
  }

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
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(title: Text(e.name)),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.only(bottom: 100 + bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // hero: a gradient panel with a large icon and soft light
                Reveal(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    width: double.infinity,
                    height: 176,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      gradient: AppTheme.heroGradient,
                      borderRadius: BorderRadius.circular(AppTheme.rHero),
                      boxShadow: AppTheme.glowShadow(blur: 30, opacity: 0.32, offset: const Offset(0, 14)),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned(
                          right: -40,
                          top: -50,
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Colors.white.withOpacity(0.24), Colors.white.withOpacity(0)])),
                          ),
                        ),
                        Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.4)),
                          child: Icon(AppIcons.exercise(e.group), size: 46, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                Reveal(
                  index: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GlassCard(padding: const EdgeInsets.symmetric(vertical: 16), child: Row(children: metrics)),
                  ),
                ),
                if (e.compendium.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                    child: Text(
                      'Energy estimate: ${e.met} METs — 2024 Compendium of Physical Activities, code ${e.compendium.replaceAll('*', '')}'
                      '${e.compendium.endsWith('*') ? ' (closest listed activity)' : ''}',
                      style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.4),
                    ),
                  ),
                const SectionHeader('Muscle groups', padding: EdgeInsets.fromLTRB(20, 22, 20, 10)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [for (final m in e.muscles) InfoChip(m)]),
                ),
                const SectionHeader('Difficulty', padding: EdgeInsets.fromLTRB(20, 22, 20, 10)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      InfoChip(e.levelLabel, icon: Icons.bolt_rounded, color: levelColor),
                      InfoChip(e.impact == 'low' ? 'Low impact' : 'High impact', icon: Icons.compress_rounded, color: AppTheme.macroFat),
                    ],
                  ),
                ),
                if (planned.reasons.isNotEmpty || e.equipment != 'none')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: GlassCard(
                      tint: AppTheme.tint(AppTheme.primary, 0.10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (planned.reasons.isNotEmpty) ...[
                            const Row(children: [
                              Icon(Icons.tips_and_updates_rounded, size: 18, color: AppTheme.primary),
                              SizedBox(width: 8),
                              Expanded(child: Text('Why this exercise for you', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.primary))),
                            ]),
                            for (final r in planned.reasons)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  const Padding(padding: EdgeInsets.only(top: 7), child: Icon(Icons.circle, size: 5, color: AppTheme.primary)),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(r, style: const TextStyle(fontSize: 13.5, color: AppTheme.textPrimary, height: 1.4, fontWeight: FontWeight.w500))),
                                ]),
                              ),
                          ],
                          if (e.equipment != 'none')
                            Padding(
                              padding: EdgeInsets.only(top: planned.reasons.isNotEmpty ? 12 : 0),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Icon(Icons.chair_alt_rounded, size: 18, color: AppTheme.textSecondary),
                                const SizedBox(width: 8),
                                Expanded(child: Text('You will need: ${e.equipment}', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w600))),
                              ]),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SectionHeader('Technique', padding: EdgeInsets.fromLTRB(20, 24, 20, 6)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    e.techniqueSource == 'free-exercise-db'
                        ? 'Muscles and technique adapted from the free-exercise-db open dataset (public domain): ${e.referenceId}'
                            '${e.referenceMatch == 'related' ? ' — closest match' : ''}. Cues are rewritten for the prescribed sets and safety.'
                        : 'Technique written by the Baymax team (no matching entry in an open dataset); pending professional review.',
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.45),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      for (var i = 0; i < e.steps.length; i++) _buildTechniqueStep('${i + 1}', e.steps[i], i),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: GlassCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const IconWell(icon: Icons.shield_rounded, color: AppTheme.teal, size: 40),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            e.impact == 'low'
                                ? 'Selected as safe for your profile. Move with control and stop if you feel sharp pain, dizziness or chest discomfort.'
                                : 'High-impact move. Land softly, keep your core braced and stop if you feel sharp pain, dizziness or chest discomfort.',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.45, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 12 + bottom,
            left: 20,
            right: 20,
            child: GlowButton(
              icon: Icons.play_arrow_rounded,
              label: 'Start exercise',
              onPressed: () {
                final q = queue.isEmpty ? [planned] : queue;
                final i = q.indexOf(planned);
                Navigator.push(context, MaterialPageRoute(builder: (_) => PostureModeSelection(queue: q, startIndex: i < 0 ? 0 : i)));
              },
            ),
          ),
        ],
      ),
    );
  }
}
