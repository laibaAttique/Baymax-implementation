import 'package:flutter/material.dart';
import 'calorie_target_screen.dart';
import '../../models/plan.dart';
import '../../services/user_session.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../../widgets/specialist_plan_banner.dart';

/// Module 3 (FR-4/FR-6): calorie target, macro breakdown and a meal plan that
/// respects the user's allergies and medical conditions.
class NutritionPlanScreen extends StatelessWidget {
  const NutritionPlanScreen({Key? key}) : super(key: key);

  Widget _macro(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.4)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _tipRow(IconData icon, Color color, String tip) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: color)),
            const SizedBox(width: 12),
            Expanded(child: Text(tip, style: const TextStyle(color: AppTheme.textPrimary, height: 1.45, fontSize: 13.5, fontWeight: FontWeight.w500))),
          ],
        ),
      );

  Widget _mealCard(String meal, NutritionPlan n, int index) {
    final items = n.meals[meal] ?? const <MealItem>[];
    return Reveal(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconWell(icon: AppIcons.meal(meal), size: 38),
                  const SizedBox(width: 12),
                  Expanded(child: Text(meal, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: AppTheme.textPrimary, letterSpacing: -0.2))),
                  Text('${n.mealKcal(meal).round()} kcal', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 6),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('No suitable foods found for your allergies — search foods in the Diet tab.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5)),
                ),
              for (final i in items)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white)),
                        child: Icon(AppIcons.food(i.food.icon), size: 20, color: AppTheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(i.food.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppTheme.textPrimary)),
                            const SizedBox(height: 1),
                            Text('${i.servingText} · ${i.food.fromUsda ? 'USDA' : 'estimate'}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      Text('${i.kcal.round()}', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w800)),
                      const Padding(padding: EdgeInsets.only(left: 3), child: Text('kcal', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserSession.instance,
      builder: (context, _) {
        final plan = UserSession.instance.plan;
        if (plan == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Nutrition plan')),
            body: const Center(child: Text('Complete your health profile to get a nutrition plan.')),
          );
        }
        final n = plan.nutrition;

        return Scaffold(
          appBar: AppBar(title: const Text('Nutrition plan')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SpecialistPlanBanner(diet: true),
                Reveal(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: AppTheme.heroGradient,
                      borderRadius: BorderRadius.circular(AppTheme.rHero),
                      boxShadow: AppTheme.glowShadow(blur: 30, opacity: 0.32, offset: const Offset(0, 14)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text('DAILY TARGET', style: AppTheme.overline.copyWith(color: Colors.white.withOpacity(0.82))),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
                            child: Text(n.goalLabel, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white)),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('${n.targetKcal}', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1.5, height: 1.1)),
                            const SizedBox(width: 6),
                            Text('kcal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.85))),
                          ],
                        )),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.rMedium)),
                          child: Row(
                            children: [
                              _macro('${n.proteinG}g', 'Protein', AppTheme.macroProtein),
                              _macro('${n.carbsG}g', 'Carbs', AppTheme.macroCarbs),
                              _macro('${n.fatG}g', 'Fat', AppTheme.macroFat),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(children: [
                          Icon(Icons.water_drop_rounded, size: 18, color: Colors.white.withOpacity(0.9)),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Drink about ${n.waterLitres.toStringAsFixed(1)} L of water', style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: 13.5, fontWeight: FontWeight.w600))),
                        ]),
                      ],
                    ),
                  ),
                ),
                if (n.calorieNote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(n.calorieNote!, style: const TextStyle(color: AppTheme.warning, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4)),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalorieTargetScreen())),
                    icon: const Icon(Icons.help_outline_rounded, size: 18),
                    label: const Text('How is my target worked out?'),
                  ),
                ),
                const SizedBox(height: 4),
                for (var i = 0; i < 4; i++) _mealCard(const ['Breakfast', 'Lunch', 'Dinner', 'Snack'][i], n, i + 1),

                const SectionHeader('Foods to avoid', padding: EdgeInsets.fromLTRB(0, 14, 0, 10)),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final a in n.avoid) InfoChip(a, icon: Icons.block_rounded, color: AppTheme.error)],
                ),
                if (n.tips.isNotEmpty) ...[
                  const SectionHeader('For your health', padding: EdgeInsets.fromLTRB(0, 26, 0, 10)),
                  GlassCard(
                    tint: AppTheme.tint(AppTheme.teal, 0.10),
                    child: Column(
                      children: [for (final tip in n.tips) _tipRow(Icons.health_and_safety_rounded, AppTheme.teal, tip)],
                    ),
                  ),
                ],
                const SectionHeader('Pro tips', padding: EdgeInsets.fromLTRB(0, 26, 0, 4)),
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text('Three new tips each day.', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ),
                GlassCard(
                  child: Column(
                    children: [for (final tip in n.tipsFor(DateTime.now())) _tipRow(Icons.lightbulb_rounded, AppTheme.warning, tip)],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Meal suggestions come from a built-in food list filtered by your allergies. Foods marked "USDA" use values from USDA FoodData Central; "estimate" means a typical-serving figure that has not been verified against a food-composition table. See Profile → Sources & methodology. This is guidance, not medical advice.',
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.45),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
