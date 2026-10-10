import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/allergen_matcher.dart';
import '../../services/api_client.dart';
import '../../services/ocr_service.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';
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

  void _analyze(String text) {
    if (text.trim().isEmpty) {
      _snack('Paste or scan an ingredient list first.');
      return;
    }
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
      appBar: AppBar(title: const Text('Allergy Scanner')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🛡️ Your allergies', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  const SizedBox(height: 8),
                  if (allergies.isEmpty)
                    const Text('No food allergies on your profile, so nothing will be flagged.',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final a in allergies)
                          Chip(
                            label: Text(a),
                            backgroundColor: AppTheme.error.withOpacity(0.1),
                            labelStyle: const TextStyle(color: AppTheme.error, fontWeight: FontWeight.w600),
                            side: BorderSide.none,
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('Scan a product label', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 4),
            const Text('Photograph the ingredient list, keeping the text flat, sharp and well lit.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : () => _scan(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Scan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _scan(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
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
                    Text(_status, style: const TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            const SizedBox(height: 28),
            const Text('Or type / paste the ingredients', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            TextField(
              controller: _textCtrl,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(hintText: 'Wheat flour, sugar, milk powder, soy oil, peanut butter, salt'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : () => _analyze(_textCtrl.text),
              child: const Text('Check ingredients'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Text recognition can miss or misread words. Always double-check the printed label if you have a serious allergy.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
