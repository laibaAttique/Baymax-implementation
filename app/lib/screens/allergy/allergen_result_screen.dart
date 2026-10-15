import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/allergen_matcher.dart';
import '../../services/inbox_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';

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
    if (r.hasDirectHit) _notify(r.allergensFound.toList());
    if (r.hasDirectHit || r.hasTraceHit) {
      HapticFeedback.heavyImpact();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (r.hasDirectHit && mounted) _showAlert();
      });
    }
  }

  /// Module 16 FR-6: an allergen found by the scanner also goes to the Notifications list and the phone's notification shade.
  Future<void> _notify(List<String> allergens) async {
    try {
      await InboxService.instance.add(InboxService.allergen(allergens, DateTime.now()), alsoOnPhone: true);
    } catch (_) {
      // Not signed in or offline: the alert dialog on this screen still warns the user.
    }
  }

  void _showAlert() {
    final r = widget.result;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, size: 52, color: AppTheme.error),
        title: const Text('ALLERGEN DETECTED', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.w800)),
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
    final IconData icon;
    final String title;
    final String subtitle;
    if (r.hasDirectHit) {
      color = AppTheme.error;
      icon = Icons.dangerous_rounded;
      title = '${r.allergensFound.length} allergen${r.allergensFound.length > 1 ? 's' : ''} found';
      subtitle = r.allergensFound.join(', ');
    } else if (r.hasTraceHit) {
      color = AppTheme.warning;
      icon = Icons.warning_amber_rounded;
      title = 'May contain traces';
      subtitle = r.traceAllergens.join(', ');
    } else {
      color = AppTheme.success;
      icon = Icons.verified_rounded;
      title = r.userAllergies.isEmpty ? 'Nothing to check against' : 'No allergens found';
      subtitle = r.userAllergies.isEmpty
          ? 'Your profile has no food allergies.'
          : 'None of ${r.userAllergies.join(', ')} were detected.';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Scan results')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Reveal(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.tint(color, 0.14),
                  borderRadius: BorderRadius.circular(AppTheme.rHero),
                  border: Border.all(color: color.withOpacity(0.55), width: 1.4),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.18), blurRadius: 28, offset: const Offset(0, 12))],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 18, offset: const Offset(0, 6))]),
                      child: Icon(icon, size: 36, color: Colors.white),
                    ),
                    const SizedBox(height: 14),
                    Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.4)),
                    const SizedBox(height: 4),
                    Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, height: 1.4)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            if (r.hasTraceHit && r.traceHits.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppTheme.tint(AppTheme.warning, 0.16), borderRadius: BorderRadius.circular(AppTheme.rMedium)),
                child: Text(
                  'The label says it may contain traces of: ${r.traceAllergens.join(', ')}. If your allergy is severe, avoid it.',
                  style: const TextStyle(color: AppTheme.warning, height: 1.45, fontWeight: FontWeight.w600),
                ),
              ),

            const SectionHeader('Ingredient analysis', padding: EdgeInsets.fromLTRB(0, 6, 0, 10)),
            if (r.ingredients.isEmpty) const Text('No ingredients could be read from the text.', style: TextStyle(color: AppTheme.textSecondary)),
            for (final i in r.ingredients)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: i.flagged ? AppTheme.error.withOpacity(0.09) : AppTheme.card,
                  borderRadius: BorderRadius.circular(AppTheme.rMedium),
                  border: Border.all(color: i.flagged ? AppTheme.error.withOpacity(0.4) : Colors.white, width: 1.2),
                ),
                child: Row(
                  children: [
                    Icon(i.flagged ? Icons.error_rounded : Icons.check_circle_rounded, size: 22, color: i.flagged ? AppTheme.error : AppTheme.success),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.text, style: TextStyle(fontWeight: i.flagged ? FontWeight.w800 : FontWeight.w600, color: AppTheme.textPrimary)),
                          if (i.flagged)
                            Text(
                              i.hits.map((h) => '${h.allergen}${h.exact ? '' : ' (possible match)'}').join(', '),
                              style: const TextStyle(fontSize: 12.5, color: AppTheme.error, fontWeight: FontWeight.w700),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            if (r.hasDirectHit)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: GlassCard(
                  tint: AppTheme.tint(AppTheme.error, 0.10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.block_rounded, color: AppTheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Recommendation: avoid this product. It contains ${r.allergensFound.join(' and ')}, which ${r.allergensFound.length > 1 ? 'are' : 'is'} on your allergy list. Look for ${r.allergensFound.map((a) => '${a.toLowerCase()}-free').join(' and ')} alternatives.',
                          style: const TextStyle(height: 1.45, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              title: const Text('Text that was read', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
              children: [Align(alignment: Alignment.centerLeft, child: Text(r.rawText, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.45)))],
            ),
            const SizedBox(height: 8),
            const Text(
              'This check can miss or misread ingredients. It is not a substitute for reading the label, especially for severe allergies.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 22),
            GlowButton(icon: Icons.document_scanner_rounded, label: 'Scan another', onPressed: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}
