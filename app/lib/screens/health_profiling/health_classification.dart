import 'package:flutter/material.dart';
import '../../services/health_classifier.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';
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

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _riskBar(String label, double risk, double baseline) {
    final high = risk >= baseline * 1.5;
    final color = high ? AppTheme.warning : AppTheme.success;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              Flexible(
                child: Text('${(risk * 100).round()}%  (average ${(baseline * 100).round()}%)',
                    textAlign: TextAlign.right, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: (risk * 2).clamp(0.0, 1.0), minHeight: 8, backgroundColor: AppTheme.border, color: color),
              ),
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (baseline * 2).clamp(0.0, 1.0),
                  child: const Align(alignment: Alignment.centerRight, child: SizedBox(width: 2, height: 8, child: ColoredBox(color: AppTheme.textPrimary))),
                ),
              ),
            ],
          ),
        ],
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
        appBar: AppBar(title: const Text('Baymax')),
        body: const Center(child: Text('Complete your health profile to see your classification.')),
      );
    }

    final riskColor = colorFor(cls.riskLevel);
    final target = plan.nutrition.targetKcal;

    return Scaffold(
      appBar: AppBar(title: const Text('Baymax')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              color: riskColor.withOpacity(0.12),
              child: Column(
                children: [
                  Text(cls.category.toUpperCase(), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: riskColor, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  _chip('${cls.riskLevel} risk', riskColor),
                  const SizedBox(height: 8),
                  const Text('AI Health Classification Result', style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Insight Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(24)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(color: AppTheme.primaryLight, shape: BoxShape.circle),
                              alignment: Alignment.center,
                              child: const Text('🤖', style: TextStyle(fontSize: 18)),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text('Baymax AI Insight', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(color: AppTheme.textSecondary, height: 1.5, fontSize: 14),
                            children: [
                              const TextSpan(text: 'Based on your BMI of '),
                              TextSpan(text: cls.bmi.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                              TextSpan(text: ' (${cls.bmiCategory}), age, activity level and medical history, you are classified as '),
                              TextSpan(text: cls.category, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                              TextSpan(text: '. ${cls.rationale}'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: AppTheme.border),
                        const SizedBox(height: 8),
                        Text('📊 Method: ${cls.method}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (cls.riskFactors.isNotEmpty) ...[
                    const Text('Risk Factors', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [for (final f in cls.riskFactors) _chip('⚠️ $f', AppTheme.warning)],
                    ),
                    const SizedBox(height: 24),
                  ],

                  if (cls.hasModelInsight) ...[
                    const Text('Statistical risk estimate', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    const SizedBox(height: 4),
                    const Text('Share of people with your BMI, age, sex and activity level who have each condition (large US health survey).',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4)),
                    const SizedBox(height: 12),
                    for (final entry in const {'Diabetic': 'Diabetes', 'Cardiac': 'Heart disease'}.entries)
                      _riskBar(entry.value, cls.modelRisk[entry.key]!, cls.modelBaseline[entry.key]!),
                    const SizedBox(height: 4),
                    const Text(
                      'Estimated from a large CDC health survey of US adults, so it may not fit people in other countries (for example, South Asians tend to develop diabetes at lower BMI). '
                      'It is a screening guide, not a diagnosis.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: AppTheme.success.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
                          child: Column(
                            children: [
                              const Text('🏃', style: TextStyle(fontSize: 24)),
                              const SizedBox(height: 8),
                              Text('${plan.intensity} Intensity', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                              Text('${plan.workoutDays}x/week planned', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Colors.blue.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
                          child: Column(
                            children: [
                              const Text('🥗', style: TextStyle(fontSize: 24)),
                              const SizedBox(height: 8),
                              Text('$target kcal/day', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                              Text(plan.nutrition.goalLabel, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Text(
                    'This is decision support, not a medical diagnosis. Please consult a doctor before starting a new exercise or diet programme.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                  ),

                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkoutPlan())),
                    child: const Text('View Workout Plan'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textPrimary,
                      side: const BorderSide(color: AppTheme.border),
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NutritionPlanScreen())),
                    child: const Text('View Nutrition Plan'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const MainNavigation()),
                        (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
                    child: const Text('Go to Dashboard →', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
