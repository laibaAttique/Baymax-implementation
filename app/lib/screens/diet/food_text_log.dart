import 'package:flutter/material.dart';
import '../../models/food.dart';
import '../../services/api_client.dart';
import '../../services/food_database.dart';
import '../../services/food_log_service.dart';
import '../../services/food_parser.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';

/// Module 7 text logging (FE-1..FE-6): describe a meal in a sentence (NLP
/// entity extraction) or search the food database, review the items, then log.
class FoodTextLog extends StatefulWidget {
  final DateTime date;

  /// 'text', or 'image' when reached from the photo screen.
  final String source;
  final bool startInSearch;

  /// Catalogue ids to pre-fill (e.g. the food recognised in a photo).
  final List<String> preselect;

  const FoodTextLog({Key? key, required this.date, this.source = 'text', this.startInSearch = false, this.preselect = const []})
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
  final List<ParsedFood> _basket = [];
  List<String> _unmatched = [];
  List<FoodItem> _results = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _searchMode = widget.startInSearch;
    final h = DateTime.now().hour;
    _meal = h < 11 ? 'Breakfast' : (h < 16 ? 'Lunch' : (h < 19 ? 'Snack' : 'Dinner'));
    FoodDatabase.load().then((db) {
      if (!mounted) return;
      setState(() {
        _db = db;
        for (final id in widget.preselect) {
          final item = db.byId(id);
          if (item != null) _basket.add(ParsedFood(raw: item.name, item: item, quantity: 1, unit: 'serving', servings: 1));
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

  List<String> get _allergies => UserSession.instance.profile?.allergies ?? const [];

  void _analyze() {
    final db = _db;
    if (db == null || _describeCtrl.text.trim().isEmpty) return;
    final parsed = FoodParser(db).parse(_describeCtrl.text);
    setState(() {
      _basket.addAll(parsed.where((p) => p.matched));
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
      _basket.add(ParsedFood(raw: item.name, item: item, quantity: 1, unit: 'serving', servings: 1));
      _searchCtrl.clear();
      _results = [];
    });
  }

  void _step(int index, double delta) {
    final p = _basket[index];
    final next = (p.servings + delta);
    setState(() {
      if (next <= 0) {
        _basket.removeAt(index);
      } else {
        _basket[index] = p.withServings(double.parse(next.toStringAsFixed(2)));
      }
    });
  }

  Future<void> _log() async {
    if (_basket.isEmpty || _saving) return;
    setState(() => _saving = true);
    final date = FoodLogService.dateKey(widget.date);
    try {
      await FoodLogService.instance.add([for (final p in _basket) p.toEntry(date: date, meal: _meal, source: widget.source)]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Logged ${_basket.length} item(s) to $_meal.')));
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
    final total = _basket.fold(0.0, (s, p) => s + p.kcal);
    final db = _db;

    return Scaffold(
      appBar: AppBar(title: const Text('Log Food')),
      body: db == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Meal', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final m in _meals)
                        ChoiceChip(
                          label: Text(m),
                          selected: _meal == m,
                          selectedColor: AppTheme.primaryLight,
                          onSelected: (_) => setState(() => _meal = m),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Describe meal'), icon: Icon(Icons.edit_note)),
                      ButtonSegment(value: true, label: Text('Search foods'), icon: Icon(Icons.search)),
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
                    ElevatedButton(onPressed: _analyze, child: const Text('Add to meal')),
                    if (_unmatched.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppTheme.warning.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            'Couldn\'t find: ${_unmatched.join(', ')}. Try "Search foods" to pick it manually.',
                            style: const TextStyle(color: AppTheme.warning, fontSize: 13),
                          ),
                        ),
                      ),
                  ] else ...[
                    TextField(
                      controller: _searchCtrl,
                      onChanged: _search,
                      decoration: const InputDecoration(hintText: 'Search e.g. chicken, rice, banana', prefixIcon: Icon(Icons.search)),
                    ),
                    for (final item in _results) _resultTile(item),
                    if (_searchCtrl.text.isNotEmpty && _results.isEmpty)
                      const Padding(padding: EdgeInsets.all(12), child: Text('No matches. Try a simpler name.', style: TextStyle(color: AppTheme.textSecondary))),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(db.originLabel, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_basket.isNotEmpty) ...[
                    const Text('Your meal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _basket.length; i++) _basketRow(i),
                  ],
                  const SizedBox(height: 100),
                ],
              ),
            ),
      bottomNavigationBar: _basket.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: _saving ? null : _log,
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Log ${total.round()} kcal to $_meal ✓'),
                ),
              ),
            ),
    );
  }

  Widget _resultTile(FoodItem item) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Text(item.icon, style: const TextStyle(fontSize: 26)),
      title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${item.kcal.round()} kcal · ${item.servingLabel} · ${item.fromUsda ? 'USDA' : 'estimate'}'),
      trailing: const Icon(Icons.add_circle, color: AppTheme.primary),
      onTap: () => _addFromSearch(item),
    );
  }

  Widget _basketRow(int i) {
    final p = _basket[i];
    final item = p.item!;
    final conflicts = item.conflictsWith(_allergies);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: conflicts.isEmpty ? null : Border.all(color: AppTheme.error),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(item.icon, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    Text('${_fmt(p.servings)} × ${item.servingLabel}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    Text('Source: ${item.sourceLabel}', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _step(i, -0.5)),
              Text('${p.kcal.round()}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
              IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _step(i, 0.5)),
            ],
          ),
          if (conflicts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '⚠️ Contains ${conflicts.join(', ')} — on your allergy list',
                style: const TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}
