import 'package:flutter/material.dart';
import '../../services/health_classifier.dart';
import '../../services/recommendations.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../dashboard/main_navigation.dart';
import '../nutrition/nutrition_plan_screen.dart';
import '../workout_and_exercise/workout_plan.dart';

/// Module 2 result screen: category, risk level, WHO BMI band, risk factors
/// and what it means for the user's plans.
class HealthClassification extends StatelessWidget {
  const HealthClassification({Key? key}) : super(key: key);

  static Color colorFor(String risk) {
    switch (risk) {
      case 'High':
        return AppTheme.error;
      case 'Moderate':
        return AppTheme.warning;
      default:
        return AppTheme.success;
    }
  }

  Widget _riskBar(String label, double risk, double baseline) {
    final high = risk >= baseline * 1.5;
    final color = high ? AppTheme.warning : AppTheme.success;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700))),
              const SizedBox(width: 8),
              Flexible(
                child: Text('${(risk * 100).round()}%  (average ${(baseline * 100).round()}%)',
                    textAlign: TextAlign.right, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: (risk * 2).clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => LinearProgressIndicator(value: v, minHeight: 9, backgroundColor: const Color(0xFFDDE0F5), color: color),
                ),
              ),
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (baseline * 2).clamp(0.0, 1.0),
                  child: const Align(alignment: Alignment.centerRight, child: SizedBox(width: 2, height: 9, child: ColoredBox(color: AppTheme.textPrimary))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _planTile(IconData icon, Color color, String title, String sub) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconWell(icon: icon, color: color, size: 40),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 14.5, letterSpacing: -0.2)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = UserSession.instance;
    final ClassificationResult? cls = session.classification;
    final profile = session.profile;
    final plan = session.plan;

    if (cls == null || profile == null || plan == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Health summary')),
        body: const Center(child: Text('Complete your health profile to see your classification.')),
      );
    }

    final riskColor = colorFor(cls.riskLevel);
    final target = plan.nutrition.targetKcal;
    final actions = recommendedActions(profile, cls, plan);

    return Scaffold(
      appBar: AppBar(title: const Text('Health summary')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner
            Reveal(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppTheme.tint(riskColor, 0.22), AppTheme.tint(riskColor, 0.08)]),
                  borderRadius: BorderRadius.circular(AppTheme.rHero),
                  border: Border.all(color: riskColor.withOpacity(0.45), width: 1.4),
                  boxShadow: [BoxShadow(color: riskColor.withOpacity(0.16), blurRadius: 28, offset: const Offset(0, 12))],
                ),
                child: Column(
                  children: [
                    const Text('HEALTH CLASSIFICATION', style: AppTheme.overline),
                    const SizedBox(height: 8),
                    Text(cls.category.toUpperCase(), textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: riskColor, letterSpacing: 0.5)),
                    const SizedBox(height: 12),
                    InfoChip('${cls.riskLevel} risk', icon: Icons.shield_rounded, color: riskColor),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Insight card
            Reveal(
              index: 1,
              child: SizedBox(
                width: double.infinity,
                child: GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          IconWell(icon: Icons.auto_awesome_rounded, size: 40),
                          SizedBox(width: 12),
                          Expanded(child: Text('Baymax insight', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.3))),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(color: AppTheme.textSecondary, height: 1.55, fontSize: 14.5, fontWeight: FontWeight.w500),
                          children: [
                            const TextSpan(text: 'Based on your BMI of '),
                            TextSpan(text: cls.bmi.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                            TextSpan(text: ' (${cls.bmiCategory}), age, activity level and medical history, you are classified as '),
                            TextSpan(text: cls.category, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                            TextSpan(text: '. ${cls.rationale}'),
                            const TextSpan(text: ' Your first step: '),
                            TextSpan(text: '${firstStep(actions).toLowerCase()}.', style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Divider(),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.analytics_outlined, size: 16, color: AppTheme.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Method: ${cls.method}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (cls.riskFactors.isNotEmpty) ...[
              const SectionHeader('Risk factors', padding: EdgeInsets.fromLTRB(0, 26, 0, 12)),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final f in cls.riskFactors) InfoChip(f, icon: Icons.warning_amber_rounded, color: AppTheme.warning)],
              ),
            ],

            if (cls.hasModelInsight) ...[
              const SectionHeader('Statistical risk estimate', padding: EdgeInsets.fromLTRB(0, 26, 0, 4)),
              const Text('Share of people with your BMI, age, sex and activity level who have each condition (large US health survey).',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.45)),
              const SizedBox(height: 10),
              GlassCard(
                child: Column(
                  children: [
                    for (final entry in const {'Diabetic': 'Diabetes', 'Cardiac': 'Heart disease'}.entries) _riskBar(entry.value, cls.modelRisk[entry.key]!, cls.modelBaseline[entry.key]!),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Estimated from a large CDC health survey of US adults, so it may not fit people in other countries (for example, South Asians tend to develop diabetes at lower BMI). '
                'It is a screening guide, not a diagnosis.',
                style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.45),
              ),
            ],

            const SectionHeader('Recommended actions', padding: EdgeInsets.fromLTRB(0, 26, 0, 12)),
            for (var i = 0; i < actions.length; i++)
              Reveal(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconWell(icon: actions[i].icon, color: AppTheme.teal, size: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(actions[i].title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppTheme.textPrimary, letterSpacing: -0.2)),
                              const SizedBox(height: 3),
                              Text(actions[i].detail, style: const TextStyle(fontSize: 13, height: 1.45, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SectionHeader('Your plan', padding: EdgeInsets.fromLTRB(0, 20, 0, 12)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _planTile(Icons.directions_run_rounded, AppTheme.success, '${plan.intensity} intensity', '${plan.workoutDays}x/week planned'),
                const SizedBox(width: 12),
                _planTile(Icons.restaurant_menu_rounded, AppTheme.teal, '$target kcal/day', plan.nutrition.goalLabel),
              ],
            ),

            const SizedBox(height: 16),
            const Text(
              'This is decision support, not a medical diagnosis. Please consult a doctor before starting a new exercise or diet programme.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.45),
            ),

            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkoutPlan())),
              icon: const Icon(Icons.fitness_center_rounded),
              label: const Text('View workout plan'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NutritionPlanScreen())),
              icon: const Icon(Icons.set_meal_rounded),
              label: const Text('View nutrition plan'),
            ),
            const SizedBox(height: 16),
            GlowButton(
              icon: Icons.arrow_forward_rounded,
              label: 'Go to dashboard',
              onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainNavigation()), (route) => false),
            ),
          ],
        ),
      ),
    );
  }
}
