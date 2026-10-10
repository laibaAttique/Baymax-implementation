import 'package:flutter/material.dart';
import '../../models/food.dart';
import '../../services/api_client.dart';
import '../../services/food_log_service.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';
import '../allergy/allergy_scanner.dart';
import '../nutrition/nutrition_plan_screen.dart';
import 'food_scan_screen.dart';
import 'food_text_log.dart';

/// Module 7: daily calorie and macro tracking (FE-6, FE-12).
class DietTracker extends StatefulWidget {
  const DietTracker({Key? key}) : super(key: key);

  @override
  State<DietTracker> createState() => _DietTrackerState();
}

class _DietTrackerState extends State<DietTracker> {
  static const _meals = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];
  static const _mealIcons = {'Breakfast': '🌅', 'Lunch': '☀️', 'Dinner': '🌙', 'Snack': '🍎'};
  static const _weekdayLetters = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late DateTime _selected;
  List<FoodEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
    FoodLogService.instance.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    FoodLogService.instance.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await FoodLogService.instance.forDate(FoodLogService.dateKey(_selected));
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _delete(FoodEntry e) async {
    if (e.id == null) return;
    try {
      await FoodLogService.instance.delete(e);
    } on ApiException catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
    }
  }

  void _openLogSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        Widget option(String icon, String title, String subtitle, Widget screen) {
          return ListTile(
            leading: Text(icon, style: const TextStyle(fontSize: 28)),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
            },
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Log Food', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                option('✏️', 'Type Food', 'Describe your meal or search the food list', FoodTextLog(date: _selected)),
                option('📷', 'Scan Food', 'Take or upload a photo of your meal', FoodScanScreen(date: _selected)),
                option('🛡️', 'Scan for Allergens', 'Check a product\'s ingredients', const AllergyScanner()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _macroBar(String label, double value, int target, Color color) {
    final frac = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              Text('${value.round()}${target > 0 ? '/${target}g' : 'g'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: frac, minHeight: 6, backgroundColor: AppTheme.border, color: color),
          ),
        ],
      ),
    );
  }

  Widget _weekStrip() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final monday = todayDate.subtract(Duration(days: todayDate.weekday - 1));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: List.generate(7, (i) {
          final day = monday.add(Duration(days: i));
          final isSel = day == _selected;
          final isFuture = day.isAfter(todayDate);
          return GestureDetector(
            onTap: isFuture
                ? null
                : () {
                    setState(() => _selected = day);
                    _load();
                  },
            child: Container(
              width: 46,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isSel ? AppTheme.primary : AppTheme.card,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text(_weekdayLetters[i], style: TextStyle(fontSize: 11, color: isSel ? Colors.white : AppTheme.textSecondary)),
                  const SizedBox(height: 4),
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSel ? Colors.white : (isFuture ? AppTheme.textSecondary.withOpacity(0.4) : AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = UserSession.instance;
    final nutrition = session.plan?.nutrition;
    final target = nutrition?.targetKcal ?? session.profile?.dailyCalorieTarget ?? 2000;

    final consumed = FoodLogService.totalKcal(_entries);
    final protein = _entries.fold(0.0, (s, e) => s + e.protein);
    final carbs = _entries.fold(0.0, (s, e) => s + e.carbs);
    final fat = _entries.fold(0.0, (s, e) => s + e.fat);
    final remaining = target - consumed.round();
    final over = remaining < 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Diet & Calories', style: TextStyle(fontSize: 16))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            _weekStrip(),
            Container(
              margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(20)),
              child: Column(
                children: [
                  Text('${consumed.round()}', style: TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: over ? AppTheme.error : AppTheme.primary)),
                  Text('of $target kcal', style: const TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: target <= 0 ? 0 : (consumed / target).clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: Colors.white,
                      color: over ? AppTheme.error : AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    over ? '${-remaining} kcal over your target' : '$remaining kcal remaining',
                    style: TextStyle(fontWeight: FontWeight.w600, color: over ? AppTheme.error : AppTheme.textPrimary),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Macronutrients', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  _macroBar('Protein', protein, nutrition?.proteinG ?? 0, Colors.redAccent),
                  _macroBar('Carbs', carbs, nutrition?.carbsG ?? 0, Colors.orange),
                  _macroBar('Fat', fat, nutrition?.fatG ?? 0, Colors.blue),
                ],
              ),
            ),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(_error!, style: const TextStyle(color: AppTheme.error)),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              )
            else
              for (final meal in _meals) _mealSection(meal),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NutritionPlanScreen())),
                child: const Text('View Nutrition Plan →'),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'log_food',
        onPressed: _openLogSheet,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Log Food', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _mealSection(String meal) {
    final items = _entries.where((e) => e.meal == meal).toList();
    final kcal = items.fold(0.0, (s, e) => s + e.kcal);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_mealIcons[meal]} $meal', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary)),
              Text('${kcal.round()} kcal', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
            ],
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Nothing logged yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ),
          for (final e in items)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.ref.startsWith('usda') ? '${e.name}  ·  USDA' : e.name,
                            style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
                        Text(
                          '${e.quantity == e.quantity.roundToDouble() ? e.quantity.toStringAsFixed(0) : e.quantity.toString()} × serving · P ${e.protein.round()}g  C ${e.carbs.round()}g  F ${e.fat.round()}g',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Text('${e.kcal.round()} kcal', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppTheme.textSecondary),
                    tooltip: 'Remove',
                    onPressed: () => _delete(e),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
