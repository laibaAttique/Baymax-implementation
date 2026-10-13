import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/food_database.dart';
import '../../services/food_image_classifier.dart';
import '../../theme/app_theme.dart';
import 'food_text_log.dart';

/// Module 7 image logging (FE-7..FE-11): take or upload a photo, let the on-device model suggest
/// the food, then confirm (and adjust the portion) before logging. If the trained model is not
/// installed, or is unsure, the user picks the food from the list instead.
class FoodScanScreen extends StatefulWidget {
  final DateTime date;
  const FoodScanScreen({Key? key, required this.date}) : super(key: key);

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
      MaterialPageRoute(builder: (_) => FoodTextLog(date: widget.date, source: 'image', startInSearch: ids.isEmpty, preselect: ids)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Food')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(24)),
                clipBehavior: Clip.antiAlias,
                child: _image == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('🍛', style: TextStyle(fontSize: 64)),
                          SizedBox(height: 12),
                          Text('Take or upload a photo of your meal', style: TextStyle(color: AppTheme.textSecondary)),
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
                    icon: const Icon(Icons.photo_camera),
                    label: Text(_image == null ? 'Camera' : 'Retake'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            if (!_classifier.available) ...[
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _image == null ? null : () => _confirm(const []), child: const Text('Choose the food →')),
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
        ElevatedButton(onPressed: () => _confirm(const []), child: const Text('Choose the food →')),
      ];
    }
    return [
      const Align(alignment: Alignment.centerLeft, child: Text('Is this…', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary))),
      const SizedBox(height: 6),
      for (final g in _guesses)
        Builder(builder: (_) {
          final item = _db!.byId(g.foodId)!;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            isThreeLine: _classifier.weakLabels.contains(g.foodId),
            leading: Text(item.icon, style: const TextStyle(fontSize: 26)),
            title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${(g.confidence * 100).round()}% match · ${item.kcal.round()} kcal per ${item.servingLabel}'
                '${_classifier.weakLabels.contains(g.foodId) ? '\nLess reliable for this dish — please double-check' : ''}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _confirm([g.foodId]),
          );
        }),
      TextButton(onPressed: () => _confirm(const []), child: const Text('None of these — search the list')),
      const Text('Calories are estimates for a standard serving; adjust the portion on the next screen.',
          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
    ];
  }

  Widget _notice(String text, Color color) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(color: color, fontSize: 13, height: 1.4)),
      );
}
