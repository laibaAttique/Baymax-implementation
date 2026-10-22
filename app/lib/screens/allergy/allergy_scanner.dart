import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/allergen_dictionary.dart';
import '../../services/allergen_matcher.dart';
import '../../services/api_client.dart';
import '../../services/ocr_service.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import 'allergen_result_screen.dart';

/// Module 8: scan a product label (FR-1), extract text with Google Vision
/// OCR (FR-2) and compare it with the user's allergies (FR-3/FR-4).
class AllergyScanner extends StatefulWidget {
  const AllergyScanner({Key? key}) : super(key: key);

  @override
  State<AllergyScanner> createState() => _AllergyScannerState();
}

class _AllergyScannerState extends State<AllergyScanner> {
  final _picker = ImagePicker();
  final _textCtrl = TextEditingController();
  bool _busy = false;
  String _status = '';

  List<String> get _allergies => UserSession.instance.profile?.allergies ?? const [];

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _scan(ImageSource source) async {
    XFile? file;
    try {
      file = await _picker.pickImage(source: source, maxWidth: 1800, imageQuality: 85);
    } catch (_) {
      _snack('Could not open the camera or gallery. Check app permissions.');
      return;
    }
    if (file == null) return;

    setState(() {
      _busy = true;
      _status = 'Reading the label…';
    });
    try {
      final text = await OcrService.instance.extractText(await file.readAsBytes());
      if (!mounted) return;
      if (text.trim().isEmpty) {
        _snack('No text found. Move closer, improve the lighting and try again.');
      } else {
        _textCtrl.text = text;
        _analyze(text);
      }
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyze(String text) async {
    if (text.trim().isEmpty) {
      _snack('Paste or scan an ingredient list first.');
      return;
    }
    await AllergenDictionary.ensureLoaded(); // the ingredient dictionary (a small bundled file) is read once
    if (!mounted) return;
    final result = AllergenMatcher.analyze(text, _allergies);
    Navigator.push(context, MaterialPageRoute(builder: (_) => AllergenResultScreen(result: result)));
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final allergies = _allergies;
    return Scaffold(
      appBar: AppBar(title: const Text('Allergy scanner')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Reveal(
              child: SizedBox(
                width: double.infinity,
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        IconWell(icon: Icons.shield_rounded, color: AppTheme.teal, size: 38),
                        SizedBox(width: 12),
                        Text('Your allergies', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary, letterSpacing: -0.2)),
                      ]),
                      const SizedBox(height: 12),
                      if (allergies.isEmpty)
                        const Text('No food allergies on your profile, so nothing will be flagged.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.4))
                      else
                        Wrap(spacing: 8, runSpacing: 8, children: [for (final a in allergies) InfoChip(a, icon: Icons.warning_amber_rounded, color: AppTheme.error)]),
                    ],
                  ),
                ),
              ),
            ),
            const SectionHeader('Scan a product label', padding: EdgeInsets.fromLTRB(0, 26, 0, 4)),
            const Text('Photograph the ingredient list, keeping the text flat, sharp and well lit.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w500)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : () => _scan(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_rounded),
                    label: const Text('Scan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _scan(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Text(_status, style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            const SectionHeader('Or type / paste the ingredients', padding: EdgeInsets.fromLTRB(0, 30, 0, 12)),
            TextField(
              controller: _textCtrl,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(hintText: 'Wheat flour, sugar, milk powder, soy oil, peanut butter, salt'),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _analyze(_textCtrl.text),
              icon: const Icon(Icons.fact_check_rounded),
              label: const Text('Check ingredients'),
            ),
            const SizedBox(height: 18),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.textSecondary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Text recognition can miss or misread words. Always double-check the printed label if you have a serious allergy.',
                    style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.45),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
