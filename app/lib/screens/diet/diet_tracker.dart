import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/food.dart';
import '../../services/api_client.dart';
import '../../services/food_log_service.dart';
import '../../services/user_session.dart';
import '../../services/water_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../../widgets/progress_ring.dart';
import '../allergy/allergy_scanner.dart';
import '../nutrition/nutrition_plan_screen.dart';
import 'daily_summary_screen.dart';
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
  static const _weekdayLetters = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late DateTime _selected;
  List<FoodEntry> _entries = [];
  bool _loading = true;
  String? _error;
  int _waterMl = 0;

  /// Meal sections the user collapsed (Module 8, mockup M22: collapsible meal sections).
  final Set<String> _collapsed = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
    FoodLogService.instance.changes.addListener(_load);
    WaterService.instance.changes.addListener(_loadWater);
    _load();
  }

  @override
  void dispose() {
    FoodLogService.instance.changes.removeListener(_load);
    WaterService.instance.changes.removeListener(_loadWater);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await FoodLogService.instance.forDate(FoodLogService.dateKey(_selected));
      _loadWater();
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

  Future<void> _loadWater() async {
    try {
      final ml = await WaterService.instance.forDate(_selected);
      if (mounted) setState(() => _waterMl = ml);
    } catch (_) {
      // Offline or signed out: the water card keeps its last value.
    }
  }

  Future<void> _addWater(int delta) async {
    final next = (_waterMl + delta).clamp(0, WaterService.maxMl);
    setState(() => _waterMl = next);
    HapticFeedback.selectionClick();
    try {
      await WaterService.instance.set(_selected, next);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      _loadWater();
    }
  }

  /// Removes an entry, with an Undo that lasts 5 seconds on screen (NFR-U8).
  Future<void> _delete(FoodEntry e) async {
    if (e.id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FoodLogService.instance.delete(e);
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(
        content: Text('Removed ${e.name}.'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            try {
              await FoodLogService.instance.restore(e);
            } on ApiException catch (err) {
              messenger.showSnackBar(SnackBar(content: Text(err.message)));
            }
          },
        ),
      ));
    } on ApiException catch (err) {
      messenger.showSnackBar(SnackBar(content: Text(err.message)));
    }
  }

  /// Opens the Log food sheet. [meal] is set when it comes from a meal section's "+" button, so food goes to that meal.
  void _openLogSheet({String? meal}) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        Widget option(IconData icon, String title, String subtitle, Widget screen) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: GlassCard(
              radius: AppTheme.rMedium + 2,
              padding: const EdgeInsets.all(14),
              semanticLabel: title,
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
              },
              child: Row(
                children: [
                  IconWell(icon: icon, size: 46),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: AppTheme.textPrimary)),
                        const SizedBox(height: 2),
                        Text(subtitle, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.3)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Align(alignment: Alignment.centerLeft, child: Text('Log food', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.4))),
                ),
                option(Icons.edit_note_rounded, 'Type food', 'Describe your meal or search the food list', FoodTextLog(date: _selected, initialMeal: meal)),
                option(Icons.photo_camera_rounded, 'Scan food', 'Take or upload a photo of your meal', FoodScanScreen(date: _selected, initialMeal: meal)),
                option(Icons.shield_rounded, 'Scan for allergens', 'Check a product\'s ingredients', const AllergyScanner()),
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
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
              ]),
              Text('${value.round()}${target > 0 ? ' / ${target}g' : 'g'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: frac),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(value: v, minHeight: 7, backgroundColor: const Color(0xFFDDE0F5), color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// Seven equal columns that fill the width. Future days are disabled.
  Widget _weekStrip() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final monday = todayDate.subtract(Duration(days: todayDate.weekday - 1));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: List.generate(7, (i) {
          final day = monday.add(Duration(days: i));
          final isSel = day == _selected;
          final isFuture = day.isAfter(todayDate);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Semantics(
                button: true,
                enabled: !isFuture,
                selected: isSel,
                label: '${_weekdayLetters[i]} ${day.day}${day == todayDate ? ', today' : ''}',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: isFuture
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          setState(() => _selected = day);
                          _load();
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      gradient: isSel ? AppTheme.buttonGradient : null,
                      color: isSel ? null : (isFuture ? AppTheme.background.withOpacity(0.5) : AppTheme.card),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: isSel ? Colors.transparent : (day == todayDate ? AppTheme.primary : Colors.white), width: day == todayDate && !isSel ? 1.6 : 1.2),
                      boxShadow: isSel ? AppTheme.glowShadow(blur: 16, opacity: 0.34, offset: const Offset(0, 6)) : const [],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_weekdayLetters[i], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isSel ? Colors.white.withOpacity(0.9) : AppTheme.textSecondary)),
                        const SizedBox(height: 4),
                        Text('${day.day}',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: isSel ? Colors.white : (isFuture ? AppTheme.textSecondary.withOpacity(0.7) : AppTheme.textPrimary))),
                      ],
                    ),
                  ),
                ),
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
    final bottomSpace = AppTheme.navSpace(context);
    final now = DateTime.now();
    final isToday = _selected.year == now.year && _selected.month == now.month && _selected.day == now.day;

    return Scaffold(
      appBar: AppBar(title: const Text('Diet')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.only(bottom: bottomSpace + 64),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(isToday ? 'Today' : '${_weekdayLetters[_selected.weekday - 1]}, ${_selected.day}/${_selected.month}',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.8)),
            ),
            _weekStrip(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
              child: GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        ProgressRing(
                          size: 112,
                          stroke: 11,
                          value: target <= 0 ? 0 : consumed / target,
                          over: over,
                          semanticLabel: '${consumed.round()} of $target calories',
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${consumed.round()}',
                                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.05, color: over ? AppTheme.error : AppTheme.textPrimary)),
                              const Text('kcal', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(over ? 'OVER TARGET' : 'REMAINING', style: AppTheme.overline),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text('${over ? -remaining : remaining}',
                                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.1, color: over ? AppTheme.error : AppTheme.primary)),
                              ),
                              Text('of $target kcal target', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 8), color: AppTheme.border.withOpacity(0.7)),
                    _macroBar('Protein', protein, nutrition?.proteinG ?? 0, AppTheme.macroProtein),
                    _macroBar('Carbs', carbs, nutrition?.carbsG ?? 0, AppTheme.macroCarbs),
                    _macroBar('Fat', fat, nutrition?.fatG ?? 0, AppTheme.macroFat),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
              child: _waterCard(session.plan?.nutrition.waterLitres),
            ),
            if (_loading)
              const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: GlassCard(
                  tint: AppTheme.tint(AppTheme.error, 0.10),
                  child: Column(
                    children: [
                      const Icon(Icons.cloud_off_rounded, color: AppTheme.error),
                      const SizedBox(height: 8),
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                ),
              )
            else
              for (var i = 0; i < _meals.length; i++) Reveal(index: i, child: _mealSection(_meals[i])),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DailySummaryScreen(date: _selected))),
                    icon: const Icon(Icons.insights_rounded, size: 18),
                    label: const Text('Daily summary'),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AllergyScanner())),
                    icon: const Icon(Icons.shield_rounded, size: 18),
                    label: const Text('Allergy scanner'),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NutritionPlanScreen())),
                    icon: const Icon(Icons.set_meal_rounded, size: 18),
                    label: const Text('View nutrition plan'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom - MediaQuery.viewPaddingOf(context).bottom + 8), // clears the floating bar
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppTheme.buttonGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppTheme.glowShadow(blur: 22, opacity: 0.38, offset: const Offset(0, 8)),
          ),
          child: Pressable(
            radius: 20,
            semanticLabel: 'Log food',
            onTap: _openLogSheet,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_rounded, color: Colors.white, size: 22),
                SizedBox(width: 8),
                Text('Log food', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// Daily water intake, kept apart from calories (Module 8, FR-5).
  Widget _waterCard(double? targetLitres) {
    final targetMl = ((targetLitres ?? 2.0) * 1000).round();
    final frac = targetMl == 0 ? 0.0 : (_waterMl / targetMl).clamp(0.0, 1.0);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const IconWell(icon: Icons.water_drop_rounded, color: AppTheme.macroFat, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Water', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary, letterSpacing: -0.2)),
                Text('${(_waterMl / 1000).toStringAsFixed(2)} of ${(targetMl / 1000).toStringAsFixed(1)} L', style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
              ]),
            ),
            IconButton(
              tooltip: 'Remove a glass (${WaterService.glassMl} ml)',
              icon: const Icon(Icons.remove_circle_outline_rounded),
              onPressed: _waterMl <= 0 ? null : () => _addWater(-WaterService.glassMl),
            ),
            IconButton(
              tooltip: 'Add a glass (${WaterService.glassMl} ml)',
              icon: const Icon(Icons.add_circle_rounded, color: AppTheme.primary, size: 30),
              onPressed: () => _addWater(WaterService.glassMl),
            ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: frac),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(value: v, minHeight: 8, backgroundColor: const Color(0xFFDDE0F5), color: AppTheme.macroFat),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mealSection(String meal) {
    final items = _entries.where((e) => e.meal == meal).toList();
    final kcal = items.fold(0.0, (s, e) => s + e.kcal);
    final open = !_collapsed.contains(meal);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: GlassCard(
        radius: AppTheme.rLarge,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // the header opens and closes the section; the + button adds food to this meal
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: '$meal, ${kcal.round()} calories, ${open ? 'expanded' : 'collapsed'}',
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => open ? _collapsed.add(meal) : _collapsed.remove(meal)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            IconWell(icon: AppIcons.meal(meal), size: 38),
                            const SizedBox(width: 12),
                            Expanded(child: Text(meal, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary, letterSpacing: -0.2))),
                            Text('${kcal.round()} kcal', style: TextStyle(color: items.isEmpty ? AppTheme.textSecondary : AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 14)),
                            const SizedBox(width: 4),
                            AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.expand_more_rounded, color: AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Add food to $meal',
                  icon: const Icon(Icons.add_circle_rounded, color: AppTheme.primary, size: 30),
                  onPressed: () => _openLogSheet(meal: meal),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !open
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 6, left: 50),
                            child: Text('Nothing logged yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w500)),
                          ),
                        for (final e in items)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onLongPress: () {
                              HapticFeedback.mediumImpact();
                              _delete(e);
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(top: 10, left: 50, right: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Semantics(
                                      onLongPressHint: 'Remove ${e.name}',
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(e.ref.startsWith('usda') ? '${e.name}  ·  USDA' : e.ref.startsWith('indb') ? '${e.name}  ·  INDB' : e.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14.5)),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${e.quantity == e.quantity.roundToDouble() ? e.quantity.toStringAsFixed(0) : e.quantity.toString()} × serving · P ${e.protein.round()}g  C ${e.carbs.round()}g  F ${e.fat.round()}g',
                                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Text('${e.kcal.round()}', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w800)),
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textSecondary),
                                    tooltip: 'Remove ${e.name}',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _delete(e),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (items.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.only(left: 50, top: 2),
                            child: Text('Long-press an item to remove it.', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
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
