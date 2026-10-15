import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The Baymax mark: a glowing rounded square with a heart-pulse glyph. Drawn from a Material icon, so there is no image asset.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({Key? key, this.size = 84}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Baymax',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: AppTheme.heroGradient,
          borderRadius: BorderRadius.circular(size * 0.32),
          border: Border.all(color: Colors.white.withOpacity(0.7), width: 1.5),
          boxShadow: [
            BoxShadow(color: AppTheme.glow.withOpacity(0.55), blurRadius: size * 0.5, offset: Offset(0, size * 0.14)),
            BoxShadow(color: AppTheme.aqua.withOpacity(0.25), blurRadius: size * 0.7, offset: Offset(-size * 0.1, size * 0.2)),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(Icons.monitor_heart_rounded, size: size * 0.54, color: Colors.white),
      ),
    );
  }
}

/// A short plain-language sheet for the Terms and Privacy links. This describes the prototype honestly; it is not a legal document.
void showLegalSheet(BuildContext context, {required bool privacy}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: [
          Text(privacy ? 'Privacy summary' : 'Terms summary', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          const Text('A plain-language summary for this university project release. It is not a legal document.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.45)),
          const SizedBox(height: 18),
          for (final line in privacy
              ? const [
                  'Your profile, food log, weights and activity are stored in your own account in Google Firebase and are not shown to other users.',
                  'If you join the leaderboard, only your chosen display name, weekly score and workout and logging counts are shared with other signed-in users.',
                  'Photos you take to scan a food label are sent to the project server and Google Cloud Vision to read the text. Food photos are classified on your phone.',
                  'Data is not yet encrypted with an extra layer on top of the database; that part of the project scope is not built.',
                ]
              : const [
                  'Baymax is decision support, not a medical device. It does not diagnose or treat any condition.',
                  'It does not replace advice from a doctor, dietitian or qualified trainer. Stop exercising and seek help if you feel pain, dizziness or chest discomfort.',
                  'Calorie, nutrition and exercise figures are estimates and may be wrong for you. Always read printed food labels if you have a serious allergy.',
                  'This release is a student project and is provided as is, without warranty.',
                ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 7), child: Icon(Icons.circle, size: 5, color: AppTheme.primary)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(line, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14.5, height: 1.5, fontWeight: FontWeight.w500))),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
