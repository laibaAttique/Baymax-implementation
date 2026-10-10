import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/allergen_matcher.dart';
import '../../theme/app_theme.dart';

/// Module 8, FR-5: scan results with a high-priority alert when an allergen
/// from the user's profile is found.
class AllergenResultScreen extends StatefulWidget {
  final ScanResult result;
  const AllergenResultScreen({Key? key, required this.result}) : super(key: key);

  @override
  State<AllergenResultScreen> createState() => _AllergenResultScreenState();
}

class _AllergenResultScreenState extends State<AllergenResultScreen> {
  @override
  void initState() {
    super.initState();
    final r = widget.result;
    if (r.hasDirectHit || r.hasTraceHit) {
      HapticFeedback.heavyImpact();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (r.hasDirectHit && mounted) _showAlert();
      });
    }
  }

  void _showAlert() {
    final r = widget.result;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        icon: const Text('⚠️', style: TextStyle(fontSize: 48)),
        title: const Text('ALLERGEN DETECTED', style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final a in r.allergensFound)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• $a (${_triggers(a)})', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 12),
            const Text('This product contains an ingredient from your allergy list. Avoid it.'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK, Got It'))],
      ),
    );
  }

  String _triggers(String allergen) {
    final terms = <String>{
      for (final i in widget.result.ingredients)
        for (final h in i.hits)
          if (h.allergen == allergen) i.text.toLowerCase(),
    };
    return terms.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final Color color;
    final String icon;
    final String title;
    final String subtitle;
    if (r.hasDirectHit) {
      color = AppTheme.error;
      icon = '⚠️';
      title = '${r.allergensFound.length} allergen${r.allergensFound.length > 1 ? 's' : ''} found';
      subtitle = r.allergensFound.join(', ');
    } else if (r.hasTraceHit) {
      color = AppTheme.warning;
      icon = '⚠️';
      title = 'May contain traces';
      subtitle = r.traceAllergens.join(', ');
    } else {
      color = AppTheme.success;
      icon = '✅';
      title = r.userAllergies.isEmpty ? 'Nothing to check against' : 'No allergens found';
      subtitle = r.userAllergies.isEmpty
          ? 'Your profile has no food allergies.'
          : 'None of ${r.userAllergies.join(', ')} were detected.';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Results')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: color)),
              child: Column(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 44)),
                  const SizedBox(height: 8),
                  Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                  const SizedBox(height: 4),
                  Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (r.hasTraceHit && r.traceHits.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppTheme.warning.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  'The label says it may contain traces of: ${r.traceAllergens.join(', ')}. If your allergy is severe, avoid it.',
                  style: const TextStyle(color: AppTheme.warning, height: 1.4),
                ),
              ),

            const Text('Ingredient Analysis', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            if (r.ingredients.isEmpty)
              const Text('No ingredients could be read from the text.', style: TextStyle(color: AppTheme.textSecondary)),
            for (final i in r.ingredients)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: i.flagged ? AppTheme.error.withOpacity(0.08) : AppTheme.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text(i.flagged ? '⚠' : '✓', style: TextStyle(fontSize: 16, color: i.flagged ? AppTheme.error : AppTheme.success, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.text, style: TextStyle(fontWeight: i.flagged ? FontWeight.bold : FontWeight.normal, color: AppTheme.textPrimary)),
                          if (i.flagged)
                            Text(
                              i.hits.map((h) => '${h.allergen}${h.exact ? '' : ' (possible match)'}').join(', '),
                              style: const TextStyle(fontSize: 12, color: AppTheme.error),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            if (r.hasDirectHit)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  '🚫 Recommendation: avoid this product. It contains ${r.allergensFound.join(' and ')}, which ${r.allergensFound.length > 1 ? 'are' : 'is'} on your allergy list. Look for ${r.allergensFound.map((a) => '${a.toLowerCase()}-free').join(' and ')} alternatives.',
                  style: const TextStyle(height: 1.4, color: AppTheme.textPrimary),
                ),
              ),

            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Text that was read', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
              children: [Text(r.rawText, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))],
            ),
            const SizedBox(height: 8),
            const Text(
              'This check can miss or misread ingredients. It is not a substitute for reading the label, especially for severe allergies.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Scan Another')),
          ],
        ),
      ),
    );
  }
}
