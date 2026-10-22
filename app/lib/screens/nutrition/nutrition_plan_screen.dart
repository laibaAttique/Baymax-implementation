import 'package:flutter/material.dart';
import 'calorie_target_screen.dart';
import '../../models/food.dart';
import '../../models/health_profile.dart';
import '../../models/plan.dart';
import '../../services/food_log_service.dart';
import '../../services/meal_plan_prefs.dart';
import '../../services/user_session.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../../widgets/specialist_plan_banner.dart';

/// Module 3 (FR-4/FR-6): calorie target, macro breakdown and a meal plan that
/// respects the user's allergies and medical conditions. The member can show another set of meals ("Regenerate meals"), choose their
/// own daily calories (inside the safe range), and log a meal or the whole day from the plan into the food log.
class NutritionPlanScreen extends StatefulWidget {
  /// Replaceable so the screen can be tested without Firebase. [onRegenerate] and [onSetKcal] return whether the choice was saved.
  final Future<bool> Function()? onRegenerate;
  final Future<bool> Function(int? kcal)? onSetKcal;
  final Future<void> Function(List<FoodEntry> entries)? onLog;
  final DateTime Function()? clock;
  const NutritionPlanScreen({Key? key, this.onRegenerate, this.onSetKcal, this.onLog, this.clock}) : super(key: key);

  @override
  State<NutritionPlanScreen> createState() => _NutritionPlanScreenState();
}

class _NutritionPlanScreenState extends State<NutritionPlanScreen> {
  bool _busy = false;
  final _logged = <String>{};

  DateTime get _now => (widget.clock ?? DateTime.now)();

  void _snack(String text, {SnackBarAction? action}) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), action: action));
  }

  Future<void> _regenerate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = await (widget.onRegenerate ?? UserSession.instance.regenerateMeals)();
      _logged.clear();
      _snack(saved ? 'Here is another set of meals for the same calories.' : 'New meals are shown, but the choice could not be saved: it lasts until you close the app.');
    } catch (_) {
      _snack('Could not change the meals. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseCalories(NutritionPlan n) async {
    final p = UserSession.instance.profile;
    if (p == null) return;
    final result = await showDialog<int?>(context: context, builder: (c) => _CaloriesDialog(profile: p, plan: n));
    if (result == null || _busy) return;
    setState(() => _busy = true);
    try {
      final saved = await (widget.onSetKcal ?? UserSession.instance.setCustomKcal)(result == -1 ? null : result);
      _logged.clear();
      _snack(result == -1 ? 'Back to the recommended calories.' : (saved ? 'Your plan now uses $result kcal a day.' : 'Your plan now uses $result kcal, but it could not be saved: it lasts until you close the app.'));
    } on ArgumentError catch (e) {
      _snack('${e.message}');
    } catch (_) {
      _snack('Could not change your calories. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The plan's meal as food-log entries for today: each food with the servings the plan gives, nutrition already scaled.
  static List<FoodEntry> entriesFor(NutritionPlan n, String meal, DateTime day) => _entries(n, meal, day);

  static List<FoodEntry> _entries(NutritionPlan n, String meal, DateTime day) => [
        for (final i in n.meals[meal] ?? const <MealItem>[])
          FoodEntry(
            date: FoodLogService.dateKey(day),
            meal: meal,
            name: i.food.name,
            quantity: double.parse(i.servings.toStringAsFixed(2)),
            unit: 'serving',
            kcal: double.parse(i.kcal.toStringAsFixed(1)),
            protein: double.parse(i.protein.toStringAsFixed(1)),
            carbs: double.parse(i.carbs.toStringAsFixed(1)),
            fat: double.parse(i.fat.toStringAsFixed(1)),
            source: 'manual',
            ref: i.food.ref,
          ),
      ];

  Future<void> _log(NutritionPlan n, List<String> meals) async {
    if (_busy) return;
    final again = meals.where(_logged.contains).toList();
    if (again.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Log again?'),
          content: Text('${again.join(', ')} ${again.length == 1 ? 'was' : 'were'} already logged from this plan today. Logging again adds the same food a second time.'),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Log again'))],
        ),
      );
      if (ok != true) return;
    }
    final entries = [for (final m in meals) ...entriesFor(n, m, _now)];
    if (entries.isEmpty) {
      _snack('There is nothing to log in that meal.');
      return;
    }
    setState(() => _busy = true);
    try {
      await (widget.onLog ?? FoodLogService.instance.add)(entries);
      _logged.addAll(meals);
      final kcal = entries.fold(0.0, (s, e) => s + e.kcal).round();
      _snack('Logged ${meals.length == 1 ? meals.first.toLowerCase() : 'your day'} ($kcal kcal) to today\'s food log.',
          action: widget.onLog == null ? SnackBarAction(label: 'Undo', onPressed: () => FoodLogService.instance.undoLast().then((_) {}, onError: (_) {})) : null);
    } catch (_) {
      _snack('Could not log it. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
                            Text('${i.servingText} · ${i.food.sourceTag}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      Text('${i.kcal.round()}', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w800)),
                      const Padding(padding: EdgeInsets.only(left: 3), child: Text('kcal', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
              if (items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _busy ? null : () => _log(n, [meal]),
                      icon: Icon(_logged.contains(meal) ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, size: 18),
                      label: Text(_logged.contains(meal) ? 'Logged today' : 'Log this meal'),
                    ),
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
                if (UserSession.instance.specialistPlans.diet != null && UserSession.instance.planChoices.specialistDiet)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text('Your calories come from your specialist\'s plan. To choose your own, switch to Baymax\'s plan at the top of this page.', style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4)),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(spacing: 10, runSpacing: 8, children: [
                      OutlinedButton.icon(onPressed: _busy ? null : _regenerate, icon: const Icon(Icons.shuffle_rounded, size: 18), label: const Text('Regenerate meals')),
                      OutlinedButton.icon(onPressed: _busy ? null : () => _chooseCalories(n), icon: const Icon(Icons.tune_rounded, size: 18), label: Text(n.custom ? 'Change my calories' : 'Set my calories')),
                    ]),
                  ),
                for (var i = 0; i < 4; i++) _mealCard(const ['Breakfast', 'Lunch', 'Dinner', 'Snack'][i], n, i + 1),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlowButton(label: 'Log my whole day', icon: Icons.playlist_add_check_rounded, onPressed: _busy ? null : () => _log(n, const ['Breakfast', 'Lunch', 'Dinner', 'Snack'])),
                ),
                if (n.meals.values.any((l) => l.any((i) => i.food.fromDataset)))
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Foods marked USDA, INDB or team list come from published food tables (the label shows which); the others are the app\'s own typical servings. '
                      'Allergens of the table foods are estimated from their names, so with an allergy the plan only uses single foods, fruit and vegetables from those tables. Always read the label.',
                      style: TextStyle(fontSize: 12, height: 1.45, color: AppTheme.textSecondary),
                    ),
                  ),

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

/// The plan-to-food-log conversion, for tests.
List<FoodEntry> entriesForTest(NutritionPlan n, String meal, DateTime day) => _NutritionPlanScreenState._entries(n, meal, day);


/// Asks for the member's own daily calories. It owns its text field, so the field is only disposed when the dialog is really gone.
/// Pops the number chosen, -1 for "use the recommended calories", or nothing for cancel.
class _CaloriesDialog extends StatefulWidget {
  final HealthProfile profile;
  final NutritionPlan plan;
  const _CaloriesDialog({required this.profile, required this.plan});

  @override
  State<_CaloriesDialog> createState() => _CaloriesDialogState();
}

class _CaloriesDialogState extends State<_CaloriesDialog> {
  late final _controller = TextEditingController(text: '${widget.plan.targetKcal}');
  String? _problem;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final bad = MealPlanPrefs.problem(_controller.text, widget.profile);
    if (bad != null) {
      setState(() => _problem = bad);
    } else {
      Navigator.pop(context, int.parse(_controller.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (lo, hi) = MealPlanPrefs.range(widget.profile);
    final n = widget.plan;
    return AlertDialog(
      title: const Text('Your daily calories'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Choose between $lo and $hi kcal a day. The meals are rebuilt for your number.', style: const TextStyle(height: 1.4)),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Calories a day', errorText: _problem),
          onChanged: (_) {
            if (_problem != null) setState(() => _problem = null);
          },
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        const Text('Eating well below your needs is not safe for most people. If you have a health condition, ask your doctor first.', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4)),
      ]),
      actions: [
        if (n.custom) TextButton(onPressed: () => Navigator.pop(context, -1), child: const Text('Use recommended')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Use this')),
      ],
    );
  }
}
