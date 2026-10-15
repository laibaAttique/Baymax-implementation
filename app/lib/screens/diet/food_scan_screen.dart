import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/food_database.dart';
import '../../services/food_image_classifier.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import 'food_text_log.dart';

/// Module 7 image logging (FE-7..FE-11): take or upload a photo, let the on-device model suggest
/// the food, then confirm (and adjust the portion) before logging. If the trained model is not
/// installed, or is unsure, the user picks the food from the list instead.
class FoodScanScreen extends StatefulWidget {
  final DateTime date;

  /// The meal slot chosen by a meal section's "+" button, passed on to the logging screen.
  final String? initialMeal;
  const FoodScanScreen({Key? key, required this.date, this.initialMeal}) : super(key: key);

  @override
  State<FoodScanScreen> createState() => _FoodScanScreenState();
}

class _FoodScanScreenState extends State<FoodScanScreen> {
  FoodImageClassifier _classifier = const UnavailableFoodImageClassifier();
  final _picker = ImagePicker();
  Uint8List? _image;
  List<FoodGuess> _guesses = const [];
  FoodDatabase? _db;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    TfliteFoodClassifier.load().then((c) {
      if (mounted) setState(() => _classifier = c);
    });
    FoodDatabase.load().then((db) {
      if (mounted) setState(() => _db = db);
    });
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _image = bytes;
        _guesses = const [];
        _busy = _classifier.available;
      });
      if (_classifier.available) {
        final found = await _classifier.classify(bytes, topK: 3);
        if (!mounted) return;
        setState(() {
          _guesses = found.where((g) => g.confidence >= _classifier.minConfidence && _db?.byId(g.foodId) != null).toList();
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the camera or gallery. Check app permissions.')),
        );
      }
    }
  }

  void _confirm(List<String> ids) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FoodTextLog(date: widget.date, source: 'image', startInSearch: ids.isEmpty, preselect: ids, initialMeal: widget.initialMeal)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan food')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: AppTheme.glass(radius: AppTheme.rHero),
                clipBehavior: Clip.antiAlias,
                child: _image == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconWell(icon: Icons.photo_camera_rounded, size: 72),
                          SizedBox(height: 16),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24),
                            child: Text('Take or upload a photo of your meal',
                                textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontSize: 15)),
                          ),
                        ],
                      )
                    : Image.memory(_image!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 12),
            if (_classifier.experimental)
              _notice('Experimental recognition model — still being validated, so it is only available in test builds. Always check the suggestion before logging.', AppTheme.warning),
            if (!_classifier.available)
              _notice('Automatic food recognition is not installed yet, so pick what you ate from the food list and we\'ll log it with the photo.', AppTheme.warning),
            if (_busy) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
            if (_classifier.available && _image != null && !_busy) ..._suggestions(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_rounded),
                    label: Text(_image == null ? 'Camera' : 'Retake'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            if (!_classifier.available) ...[
              const SizedBox(height: 12),
              GlowButton(icon: Icons.restaurant_menu_rounded, label: 'Choose the food', onPressed: _image == null ? null : () => _confirm(const [])),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _suggestions() {
    if (_guesses.isEmpty) {
      return [
        _notice('I\'m not sure what this is. Pick it from the list.', AppTheme.warning),
        const SizedBox(height: 8),
        GlowButton(icon: Icons.restaurant_menu_rounded, label: 'Choose the food', onPressed: () => _confirm(const [])),
      ];
    }
    return [
      const Align(alignment: Alignment.centerLeft, child: Text('Is this…', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary))),
      const SizedBox(height: 8),
      for (final g in _guesses)
        Builder(builder: (_) {
          final item = _db!.byId(g.foodId)!;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassCard(
              radius: AppTheme.rMedium,
              padding: const EdgeInsets.all(12),
              onTap: () => _confirm([g.foodId]),
              child: Row(
                children: [
                  IconWell(icon: AppIcons.food(item.icon), size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                        Text('${(g.confidence * 100).round()}% match · ${item.kcal.round()} kcal per ${item.servingLabel}',
                            style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                        if (_classifier.weakLabels.contains(g.foodId))
                          const Text('Less reliable for this dish — please double-check', style: TextStyle(fontSize: 12, color: AppTheme.warning, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                ],
              ),
            ),
          );
        }),
      TextButton(onPressed: () => _confirm(const []), child: const Text('None of these — search the list')),
      const Text('Calories are estimates for a standard serving; adjust the portion on the next screen.',
          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
    ];
  }

  Widget _notice(String text, Color color) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTheme.tint(color, 0.16), borderRadius: BorderRadius.circular(AppTheme.rSmall + 2)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_rounded, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13, height: 1.4, fontWeight: FontWeight.w600))),
        ]),
      );
}
