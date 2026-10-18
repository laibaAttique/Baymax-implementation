import 'package:flutter/material.dart';

import '../../models/plan.dart';
import '../../models/workout_session.dart';
import '../../services/workout_session/plan_progress.dart';
import '../../services/met_calculator.dart';
import '../../services/user_session.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/exercise_visual.dart';
import '../../widgets/glass.dart';
import '../posture_detection/posture_mode.dart';

/// One exercise as prescribed in the user's plan (report Module 4, FR-6 / mockup M14): photos, metrics, muscles,
/// difficulty, why it was chosen, the safety rules that shaped it, technique steps with their source, and the hand-off
/// to Module 5 (camera detection or manual guidance).
class ExerciseDetail extends StatelessWidget {
  final PlannedExercise planned;
  final List<String> safetyNotes;

  /// The whole session this exercise belongs to; guidance walks through it from [planned] onward.
  final List<PlannedExercise> queue;

  /// The plan day (0 = Monday) [queue] belongs to, so the session is linked to the planned exercise (Module 4 progress).
  final int? weekday;

  const ExerciseDetail({super.key, required this.planned, this.safetyNotes = const [], this.queue = const [], this.weekday});

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
                decoration: BoxDecoration(
                    gradient: AppTheme.buttonGradient,
                    shape: BoxShape.circle,
                    boxShadow: AppTheme.glowShadow(blur: 10, opacity: 0.28, offset: const Offset(0, 3))),
                alignment: Alignment.center,
                child: Text(num, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(text,
                          style: const TextStyle(color: AppTheme.textPrimary, height: 1.45, fontSize: 14.5, fontWeight: FontWeight.w500)))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bullets(String title, IconData icon, Color color, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: color))),
        ]),
        for (final r in items)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 7), child: Icon(Icons.circle, size: 5, color: color)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(r, style: const TextStyle(fontSize: 13.5, color: AppTheme.textPrimary, height: 1.4, fontWeight: FontWeight.w500))),
            ]),
          ),
      ],
    );
  }

  /// Where the energy estimate comes from, and how sure the match is.
  String _energyLine(Exercise e) {
    if (!e.hasMet) {
      return 'No reliable 2024 Compendium activity matches this exercise, so no energy estimate is shown.';
    }
    final code = e.compendium.replaceAll('*', '');
    final what = e.metDescription.isEmpty ? '' : ' “${e.metDescription}”';
    final match = e.metMatch == 'exact' ? 'exact match' : 'approximate match (closest listed activity, pending review)';
    final band = e.intensityBand!;
    return 'Energy estimate: ${e.met} METs (${band.label.toLowerCase()} intensity, ${band.range}) — 2024 Adult Compendium of '
        'Physical Activities, code $code$what; $match.';
  }

  String _techniqueSource(Exercise e) {
    if (e.source == 'free-exercise-db') {
      return 'Instructions from the free-exercise-db open dataset (public domain), shown as published: ${e.referenceId}. '
          'They have not been reviewed by the Baymax team or a professional — follow the sets and reps above, not any '
          '"as many as possible" wording.';
    }
    if (e.techniqueSource == 'free-exercise-db') {
      return 'Muscles and technique adapted from the free-exercise-db open dataset (public domain): ${e.referenceId}'
          '${e.referenceMatch == 'related' ? ' — closest match' : ''}. Cues are rewritten for the prescribed sets and safety.';
    }
    return 'Technique written by the Baymax team (no matching entry in an open dataset); pending professional review.';
  }

  @override
  Widget build(BuildContext context) {
    final e = planned.exercise;
    final levelColor = e.level == 1 ? AppTheme.success : (e.level == 2 ? AppTheme.warning : AppTheme.error);
    final minutes = (planned.totalSeconds / 60).ceil();
    final weight = UserSession.instance.profile?.weightKg ?? 0;
    final kcal = MetCalculator.kcalCompendium(
      met: e.hasMet ? e.met : null,
      weightKg: weight,
      active: Duration(seconds: planned.activeSeconds),
    );
    final visual = ExerciseVisualInfo.of(e);

    final metrics = planned.timed
        ? [
            if (planned.sets > 1) _buildMetricMini('${planned.sets}', 'Sets'),
            _buildMetricMini(
                planned.seconds >= 120 ? '${(planned.seconds / 60).round()}m' : '${planned.seconds}s', planned.sets > 1 ? 'Per set' : 'Duration'),
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
                Reveal(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                    child: visual.kind == VisualKind.none
                        ? Container(
                            width: double.infinity,
                            height: 176,
                            decoration: BoxDecoration(
                              gradient: AppTheme.heroGradient,
                              borderRadius: BorderRadius.circular(AppTheme.rHero),
                              boxShadow: AppTheme.glowShadow(blur: 30, opacity: 0.32, offset: const Offset(0, 14)),
                            ),
                            alignment: Alignment.center,
                            child: Container(
                              width: 92,
                              height: 92,
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.4)),
                              child: Icon(AppIcons.exercise(e.group), size: 46, color: Colors.white),
                            ),
                          )
                        : ExerciseVisual(exercise: e, height: 220),
                  ),
                ),
                if (visual.kind != VisualKind.none)
                  Padding(
                    key: const ValueKey('visual-caption'),
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                    child: Text(visual.caption, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  ),
                Reveal(
                  index: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(children: [
                        ...metrics,
                        if (kcal != null) _buildMetricMini('≈${kcal.round()}', 'kcal'),
                      ]),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                  child: Text(
                    '${_energyLine(e)}${kcal != null ? ' Calories ≈ MET × your weight × active time (rest excluded); an approximate figure, not a measurement.' : ''}',
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
                      InfoChip(e.impact == 'low' ? 'Low impact' : (e.impact == 'high' ? 'High impact' : 'Impact not recorded'),
                          icon: Icons.compress_rounded, color: AppTheme.macroFat),
                    ],
                  ),
                ),
                if (planned.reasons.isNotEmpty || planned.ruleNotes.isNotEmpty || e.equipment != 'none')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: GlassCard(
                      tint: AppTheme.tint(AppTheme.primary, 0.10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (planned.reasons.isNotEmpty)
                            _bullets('Why this exercise for you', Icons.tips_and_updates_rounded, AppTheme.primary, planned.reasons),
                          if (planned.ruleNotes.isNotEmpty) ...[
                            if (planned.reasons.isNotEmpty) const SizedBox(height: 14),
                            _bullets('Adapted for you by the safety rules', Icons.health_and_safety_rounded, AppTheme.teal, planned.ruleNotes),
                          ],
                          if (e.equipment != 'none')
                            Padding(
                              padding: EdgeInsets.only(top: planned.reasons.isNotEmpty || planned.ruleNotes.isNotEmpty ? 12 : 0),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Icon(Icons.chair_alt_rounded, size: 18, color: AppTheme.textSecondary),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text('You will need: ${e.equipment}',
                                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w600))),
                              ]),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SectionHeader('Technique', padding: EdgeInsets.fromLTRB(20, 24, 20, 6)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(_techniqueSource(e), style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.45)),
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
                            '${e.impact == 'high' ? 'High-impact move: land softly and keep your core braced. ' : 'Move with control. '}'
                            'No recorded restriction excludes this exercise for you under the current rules, which are pending professional review — '
                            'this is not medical clearance. Stop if you feel sharp pain, dizziness or chest discomfort.',
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
                // Hand-off to Module 5: camera detection where supported, manual guidance otherwise.
                final idx = queue.indexOf(planned);
                final upNext = idx >= 0 ? queue.sublist(idx + 1) : queue.where((p) => p != planned).toList();
                final day = weekday;
                final link = day != null && idx >= 0 ? PlanProgress.instance.linkFor(day, idx) : null;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => PostureModeSelection(request: WorkoutSessionRequest.fromPlanned(planned, upNext: upNext, plan: link))),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
