import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/food.dart';
import '../../services/api_client.dart';
import '../../services/food_database.dart';
import '../../services/food_log_service.dart';
import '../../services/food_parser.dart';
import '../../services/user_session.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';

/// Module 7 text logging (FE-1..FE-6): describe a meal in a sentence (NLP
/// entity extraction) or search the food database, review the items, then log.
class FoodTextLog extends StatefulWidget {
  final DateTime date;

  /// 'text', or 'image' when reached from the photo screen.
  final String source;
  final bool startInSearch;

  /// Catalogue ids to pre-fill (e.g. the food recognised in a photo).
  final List<String> preselect;

  /// The meal slot to log into, when the user came from a meal's "+" button. Otherwise it follows the time of day.
  final String? initialMeal;

  const FoodTextLog({Key? key, required this.date, this.source = 'text', this.startInSearch = false, this.preselect = const [], this.initialMeal})
      : super(key: key);

  @override
  State<FoodTextLog> createState() => _FoodTextLogState();
}

class _FoodTextLogState extends State<FoodTextLog> {
  static const _meals = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

  final _describeCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  FoodDatabase? _db;
  late bool _searchMode;
  late String _meal;
  final List<_BasketItem> _basket = [];
  List<String> _recent = [];
  List<String> _unmatched = [];
  List<FoodItem> _results = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _searchMode = widget.startInSearch;
    final h = DateTime.now().hour;
    _meal = widget.initialMeal ?? (h < 11 ? 'Breakfast' : (h < 16 ? 'Lunch' : (h < 19 ? 'Snack' : 'Dinner')));
    _loadRecent();
    FoodDatabase.load().then((db) {
      if (!mounted) return;
      setState(() {
        _db = db;
        for (final id in widget.preselect) {
          final item = db.byId(id);
          if (item != null) _basket.add(_BasketItem(ParsedFood(raw: item.name, item: item, quantity: 1, unit: 'serving', servings: 1)));
        }
      });
    });
  }

  @override
  void dispose() {
    _describeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Foods the user logged in the last week, newest first: quick re-entry chips (mockup M23).
  Future<void> _loadRecent() async {
    try {
      final today = DateTime.now();
      final lists = await Future.wait([for (var i = 0; i < 7; i++) FoodLogService.instance.forDate(FoodLogService.dateKey(today.subtract(Duration(days: i))))]);
      final names = <String>[];
      for (final day in lists) {
        for (final e in day.reversed) {
          if (!names.contains(e.name)) names.add(e.name);
        }
      }
      if (mounted) setState(() => _recent = names.take(8).toList());
    } catch (_) {
      // Offline or signed out: no recent chips.
    }
  }

  List<String> get _allergies => UserSession.instance.profile?.allergies ?? const [];

  void _analyze() {
    final db = _db;
    if (db == null || _describeCtrl.text.trim().isEmpty) return;
    final parsed = FoodParser(db).parse(_describeCtrl.text);
    setState(() {
      _basket.addAll(parsed.where((p) => p.matched).map(_BasketItem.new));
      _unmatched = parsed.where((p) => !p.matched).map((p) => p.raw).toList();
      if (parsed.isNotEmpty) _describeCtrl.clear();
    });
    if (parsed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('I couldn\'t find any foods in that. Try "2 rotis and daal".')));
    }
  }

  void _search(String q) {
    setState(() => _results = _db?.search(q, limit: 12) ?? const []);
  }

  void _addFromSearch(FoodItem item) {
    setState(() {
      _basket.add(_BasketItem(ParsedFood(raw: item.name, item: item, quantity: 1, unit: 'serving', servings: 1)));
      _searchCtrl.clear();
      _results = [];
    });
  }

  /// One step of the +/- control: half a serving, or 25 g / ml.
  void _step(int index, int direction) {
    final b = _basket[index];
    final item = b.food.item!;
    final deltaServings = b.unit == 'serving' ? 0.5 : (item.grams > 0 ? 25 / item.grams : 0.5);
    final next = b.food.servings + direction * deltaServings;
    setState(() {
      if (next <= 0.001) {
        _basket.removeAt(index);
      } else {
        _basket[index] = b.withFood(b.food.withServings(double.parse(next.toStringAsFixed(3))));
      }
    });
  }

  void _setUnit(int index, String unit) => setState(() => _basket[index] = _basket[index].withUnit(unit));

  Future<void> _log() async {
    if (_basket.isEmpty || _saving) return;
    setState(() => _saving = true);
    final date = FoodLogService.dateKey(widget.date);
    try {
      await FoodLogService.instance.add([for (final p in _basket) p.food.toEntry(date: date, meal: _meal, source: widget.source)]);
      if (!mounted) return;
      // NFR-U8: a visible Undo for 5 seconds; the entry can be undone for 30 seconds in total.
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(
        content: Text('Logged ${_basket.length} item(s) to $_meal.'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            try {
              final n = await FoodLogService.instance.undoLast();
              messenger.showSnackBar(SnackBar(content: Text(n == 0 ? 'That was too long ago to undo.' : 'Removed $n item(s).')));
            } on ApiException catch (e) {
              messenger.showSnackBar(SnackBar(content: Text(e.message)));
            }
          },
        ),
      ));
      // Back to the tracker (the photo screen sits in between when source is 'image').
      var screensToClose = widget.source == 'image' ? 2 : 1;
      Navigator.of(context).popUntil((_) => screensToClose-- <= 0);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final total = _basket.fold(0.0, (s, p) => s + p.food.kcal);
    final db = _db;

    return Scaffold(
      appBar: AppBar(title: const Text('Log food')),
      body: db == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('MEAL', style: AppTheme.overline),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in _meals)
                        ChoiceChip(
                          avatar: Icon(AppIcons.meal(m), size: 18, color: _meal == m ? Colors.white : AppTheme.textSecondary),
                          label: Text(m),
                          selected: _meal == m,
                          showCheckmark: false,
                          selectedColor: AppTheme.primary,
                          backgroundColor: AppTheme.card,
                          side: BorderSide(color: _meal == m ? AppTheme.primary : AppTheme.border),
                          labelStyle: TextStyle(fontWeight: FontWeight.w800, color: _meal == m ? Colors.white : AppTheme.textPrimary),
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            setState(() => _meal = m);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      backgroundColor: AppTheme.card,
                      foregroundColor: AppTheme.textPrimary,
                      selectedBackgroundColor: AppTheme.primary,
                      selectedForegroundColor: Colors.white,
                      side: const BorderSide(color: AppTheme.border),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    segments: const [
                      ButtonSegment(value: false, label: Text('Describe meal'), icon: Icon(Icons.edit_note_rounded)),
                      ButtonSegment(value: true, label: Text('Search foods'), icon: Icon(Icons.search_rounded)),
                    ],
                    selected: {_searchMode},
                    onSelectionChanged: (s) => setState(() => _searchMode = s.first),
                  ),
                  const SizedBox(height: 16),
                  if (!_searchMode) ...[
                    TextField(
                      controller: _describeCtrl,
                      minLines: 2,
                      maxLines: 4,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        hintText: 'e.g. 2 rotis and a bowl of daal, 1 glass milk',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(onPressed: _analyze, icon: const Icon(Icons.add_rounded), label: const Text('Add to meal')),
                    if (_unmatched.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppTheme.tint(AppTheme.warning, 0.16), borderRadius: BorderRadius.circular(AppTheme.rSmall + 2)),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Icon(Icons.info_rounded, size: 18, color: AppTheme.warning),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Couldn\'t find: ${_unmatched.join(', ')}. Try "Search foods" to pick it manually.',
                                style: const TextStyle(color: AppTheme.warning, fontSize: 13, fontWeight: FontWeight.w600, height: 1.4),
                              ),
                            ),
                          ]),
                        ),
                      ),
                  ] else ...[
                    TextField(
                      controller: _searchCtrl,
                      onChanged: _search,
                      decoration: const InputDecoration(hintText: 'Search e.g. chicken, rice, banana', prefixIcon: Icon(Icons.search_rounded)),
                    ),
                    if (_recent.isNotEmpty && _searchCtrl.text.isEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('RECENT', style: AppTheme.overline),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final r in _recent)
                            ActionChip(
                              avatar: const Icon(Icons.history_rounded, size: 16, color: AppTheme.primary),
                              label: Text(r, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppTheme.textPrimary)),
                              side: BorderSide(color: AppTheme.primary.withOpacity(0.3)),
                              backgroundColor: AppTheme.card,
                              onPressed: () {
                                _searchCtrl.text = r;
                                _search(r);
                              },
                            ),
                        ],
                      ),
                    ],
                    if (_searchCtrl.text.trim().isNotEmpty) _suggestions(),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(db.originLabel, style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.4)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_basket.isNotEmpty) ...[
                    const Text('Your meal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.3)),
                    const SizedBox(height: 10),
                    for (var i = 0; i < _basket.length; i++) _basketRow(i),
                  ],
                  const SizedBox(height: 90),
                ],
              ),
            ),
      bottomNavigationBar: _basket.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: GlowButton(
                  icon: Icons.check_rounded,
                  loading: _saving,
                  label: 'Log ${total.round()} kcal to $_meal',
                  onPressed: _saving ? null : _log,
                ),
              ),
            ),
    );
  }

  /// The dropdown under the search box: foods whose name or another name (for example "chawal" for rice) matches what was typed.
  Widget _suggestions() {
    final q = _searchCtrl.text.trim();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.rMedium),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow(),
      ),
      clipBehavior: Clip.antiAlias,
      child: _results.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No matching foods. Try a simpler or shorter name.', style: TextStyle(color: AppTheme.textSecondary, height: 1.4)),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1, thickness: 1, color: AppTheme.border),
                itemBuilder: (_, i) => _suggestionRow(_results[i], q),
              ),
            ),
    );
  }

  /// The other name that matched [query], when the food's own name does not contain it ("also called Chawal").
  String? _matchedAlias(FoodItem item, String query) {
    final q = query.toLowerCase();
    if (item.name.toLowerCase().contains(q)) return null;
    for (final a in item.aliases) {
      if (a.toLowerCase().contains(q)) return a;
    }
    return null;
  }

  Widget _suggestionRow(FoodItem item, String query) {
    final alias = _matchedAlias(item, query);
    final conflicts = item.conflictsWith(_allergies);
    final detail = '${item.servingLabel} · ${item.kcal.round()} kcal · ${item.sourceTag}';
    return Semantics(
      button: true,
      label: 'Add ${item.name}. $detail${conflicts.isEmpty ? '' : '. Contains ${conflicts.join(', ')}, which is on your allergy list'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _addFromSearch(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              IconWell(icon: AppIcons.food(item.icon), size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary, fontSize: 14.5)),
                    if (alias != null)
                      Text('Also called $alias', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w700)),
                    Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                    if (conflicts.isNotEmpty)
                      Text('Contains ${conflicts.join(', ')} (on your allergy list)', style: const TextStyle(fontSize: 12, color: AppTheme.error, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(conflicts.isEmpty ? Icons.add_circle_rounded : Icons.warning_amber_rounded, color: conflicts.isEmpty ? AppTheme.primary : AppTheme.error, size: 26),
            ],
          ),
        ),
      ),
    );
  }

  Widget _basketRow(int i) {
    final b = _basket[i];
    final p = b.food;
    final item = p.item!;
    final conflicts = item.conflictsWith(_allergies);
    final amount = b.unit == 'serving' ? p.servings : p.servings * item.grams;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: conflicts.isEmpty ? AppTheme.card : AppTheme.tint(AppTheme.error, 0.10),
        borderRadius: BorderRadius.circular(AppTheme.rMedium + 2),
        border: Border.all(color: conflicts.isEmpty ? Colors.white : AppTheme.error, width: conflicts.isEmpty ? 1.2 : 1.5),
        boxShadow: AppTheme.softShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconWell(icon: AppIcons.food(item.icon), size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                    Text('1 ${item.servingLabel} = ${item.kcal.round()} kcal', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                    Text('Source: ${item.sourceLabel}', style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              Text('${p.kcal.round()} kcal', style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primary)),
            ],
          ),
          const SizedBox(height: 10),
          // portion size: a number with - / + and a unit (serving, g or ml); the calories above follow it live
          Row(
            children: [
              IconButton(icon: const Icon(Icons.remove_circle_outline_rounded), tooltip: 'Less', onPressed: () => _step(i, -1)),
              Expanded(
                child: Text(
                  b.unit == 'serving' ? _fmt(amount) : '${amount.round()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                ),
              ),
              IconButton(icon: const Icon(Icons.add_circle_outline_rounded), tooltip: 'More', onPressed: () => _step(i, 1)),
            ],
          ),
          // on its own line so it fits a narrow phone
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              segments: const [ButtonSegment(value: 'serving', label: Text('serving')), ButtonSegment(value: 'g', label: Text('g')), ButtonSegment(value: 'ml', label: Text('ml'))],
              selected: {b.unit},
              onSelectionChanged: (v) => _setUnit(i, v.first),
            ),
          ),
          if (b.unit == 'ml')
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text('Millilitres are treated as grams, which suits water-based drinks.', style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
            ),
          if (item.allergensEstimated && _allergies.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Allergens for this food are estimated from its name, not checked. Read the label if your allergy is serious.',
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.35)),
            ),
          if (conflicts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, size: 18, color: AppTheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Contains ${conflicts.join(', ')} — on your allergy list',
                      style: const TextStyle(color: AppTheme.error, fontSize: 12.5, fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

/// One food in the meal being built, with the unit the user chose to see its amount in.
class _BasketItem {
  final ParsedFood food;

  /// 'serving', 'g' or 'ml'. The logged quantity is always stored in servings.
  final String unit;
  const _BasketItem(this.food, [this.unit = 'serving']);

  _BasketItem withFood(ParsedFood f) => _BasketItem(f, unit);
  _BasketItem withUnit(String u) => _BasketItem(food, u);
}
