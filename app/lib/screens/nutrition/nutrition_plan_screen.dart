import 'package:flutter/material.dart';
import '../../models/plan.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';

/// Module 3 (FR-4/FR-6): calorie target, macro breakdown and a meal plan that
/// respects the user's allergies and medical conditions.
class NutritionPlanScreen extends StatelessWidget {
  const NutritionPlanScreen({Key? key}) : super(key: key);

  static const _mealIcons = {'Breakfast': '🌅', 'Lunch': '☀️', 'Dinner': '🌙', 'Snack': '🍎'};

  Widget _macro(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _mealCard(String meal, NutritionPlan n) {
    final items = n.meals[meal] ?? const <MealItem>[];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_mealIcons[meal]} $meal', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary)),
              Text('${n.mealKcal(meal).round()} kcal', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Text('No suitable foods found for your allergies — search foods in the Diet tab.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text(i.food.icon, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.food.name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                        Text('${i.servingText} · ${i.food.fromUsda ? 'USDA' : 'estimate'}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  Text('${i.kcal.round()} kcal', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                ],
              ),
            ),
        ],
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
            appBar: AppBar(title: const Text('Nutrition Plan')),
            body: const Center(child: Text('Complete your health profile to get a nutrition plan.')),
          );
        }
        final n = plan.nutrition;

        return Scaffold(
          appBar: AppBar(title: const Text('Nutrition Plan')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: Text('Nutrition Plan',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(12)),
                      child: Text(n.goalLabel.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      const Text('DAILY TARGET', style: TextStyle(color: AppTheme.textSecondary, letterSpacing: 1, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('${n.targetKcal} kcal', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _macro('${n.proteinG}g', 'Protein', Colors.redAccent),
                          _macro('${n.carbsG}g', 'Carbs', Colors.orange),
                          _macro('${n.fatG}g', 'Fat', Colors.blue),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('💧 Drink about ${n.waterLitres.toStringAsFixed(1)} L of water', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
                if (n.calorieNote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(n.calorieNote!, style: const TextStyle(color: AppTheme.warning, fontSize: 12)),
                  ),
                const SizedBox(height: 20),

                for (final meal in const ['Breakfast', 'Lunch', 'Dinner', 'Snack']) _mealCard(meal, n),

                const SizedBox(height: 8),
                const Text('🚫 Foods to Avoid', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in n.avoid)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                        child: Text(a, style: const TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('💡 Pro Tips', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                const SizedBox(height: 8),
                for (final tip in n.tips)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('• $tip', style: const TextStyle(color: AppTheme.textSecondary, height: 1.4)),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Meal suggestions come from a built-in food list filtered by your allergies. Foods marked "USDA" use values from USDA FoodData Central; "estimate" means a typical-serving figure that has not been verified against a food-composition table. See Profile → Sources & methodology. This is guidance, not medical advice.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}
