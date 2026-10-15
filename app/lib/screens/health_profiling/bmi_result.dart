import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/health_profile.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import 'health_classification.dart';

/// Module 1 results: BMI (FE-6), BMR (FE-7) and daily calories (FE-8),
/// all computed from the profile the user just entered.
class BmiResult extends StatefulWidget {
  final HealthProfile profile;
  final String? profileId;

  const BmiResult({Key? key, required this.profile, this.profileId})
    : super(key: key);

  @override
  _BmiResultState createState() => _BmiResultState();
}

class _BmiResultState extends State<BmiResult> {
  late String _selected; // 'Deficit' | 'Maintain' | 'Surplus'

  @override
  void initState() {
    super.initState();
    switch (widget.profile.primaryGoal) {
      case 'Lose Weight':
        _selected = 'Deficit';
      case 'Gain Muscle':
        _selected = 'Surplus';
      default:
        _selected = 'Maintain';
    }
  }

  Color _categoryColor(double bmi) {
    if (bmi < 18.5) return AppTheme.macroFat;
    if (bmi < 25) return AppTheme.success;
    if (bmi < 30) return AppTheme.warning;
    return AppTheme.error;
  }

  String _fmt(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );

  Widget _buildCaloriePill(String title, int kcal) {
    final isSelected = _selected == title;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Semantics(
          button: true,
          selected: isSelected,
          label: '$title, ${_fmt(kcal)} calories',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selected = title);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: isSelected ? AppTheme.buttonGradient : null,
                color: isSelected ? null : AppTheme.background,
                borderRadius: BorderRadius.circular(AppTheme.rMedium),
                border: Border.all(
                  color: isSelected ? Colors.transparent : Colors.white,
                  width: 1.2,
                ),
                boxShadow: isSelected
                    ? AppTheme.glowShadow(
                        blur: 14,
                        opacity: 0.3,
                        offset: const Offset(0, 5),
                      )
                    : const [],
              ),
              child: Column(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? Colors.white.withOpacity(0.9)
                          : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _fmt(kcal),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: isSelected ? Colors.white : AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final bmi = p.bmi;
    final targets = p.calorieTargets;
    final selectedKcal = switch (_selected) {
      'Deficit' => targets.deficit,
      'Surplus' => targets.surplus,
      _ => targets.maintain,
    };
    // Position of the marker on a 15–40 BMI scale.
    final markerFraction = ((bmi - 15) / 25).clamp(0.0, 1.0);
    final color = _categoryColor(bmi);

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(
            children: [
              Reveal(
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppTheme.success,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.success.withOpacity(0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Your profile is ready',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.7,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Here is what we worked out from your details.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // BMI card
              Reveal(
                index: 1,
                child: GlassCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      const Text('YOUR BMI', style: AppTheme.overline),
                      const SizedBox(height: 4),
                      Text(
                        bmi.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          letterSpacing: -2,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          p.bmiCategory,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, c) {
                          // BMI 15-40 mapped to the track: under 18.5, normal to 25, over to 30, obese beyond.
                          return SizedBox(
                            height: 18,
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 14,
                                        child: Container(
                                          height: 10,
                                          color: AppTheme.macroFat.withOpacity(
                                            0.75,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 26,
                                        child: Container(
                                          height: 10,
                                          color: AppTheme.success.withOpacity(
                                            0.8,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 20,
                                        child: Container(
                                          height: 10,
                                          color: AppTheme.warning.withOpacity(
                                            0.8,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 40,
                                        child: Container(
                                          height: 10,
                                          color: AppTheme.error.withOpacity(
                                            0.8,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: markerFraction),
                                  duration: const Duration(milliseconds: 800),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, v, _) => Positioned(
                                    left: (c.maxWidth - 18) * v,
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppTheme.textPrimary,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Under',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Text(
                            'Normal',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Text(
                            'Over',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Text(
                            'Obese',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // BMR card
              Reveal(
                index: 2,
                child: SizedBox(
                  width: double.infinity,
                  child: GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'BASAL METABOLIC RATE',
                          style: AppTheme.overline,
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                _fmt(p.bmr.round()),
                                style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary,
                                  letterSpacing: -1.2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'kcal/day',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Mifflin-St Jeor equation · with ${p.activityLevel.toLowerCase()} activity you burn about ${_fmt(p.tdee.round())} kcal/day',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (p.age == null)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Age assumed to be 30 — add your date of birth for a precise value.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.warning,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Calorie card
              Reveal(
                index: 3,
                child: SizedBox(
                  width: double.infinity,
                  child: GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'RECOMMENDED DAILY INTAKE',
                          style: AppTheme.overline,
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                _fmt(selectedKcal),
                                style: const TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primary,
                                  letterSpacing: -1.2,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'kcal',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _buildCaloriePill('Deficit', targets.deficit),
                            _buildCaloriePill('Maintain', targets.maintain),
                            _buildCaloriePill('Surplus', targets.surplus),
                          ],
                        ),
                        if (targets.safetyNote != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Text(
                              targets.safetyNote!,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.warning,
                                fontWeight: FontWeight.w700,
                                height: 1.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),
              GlowButton(
                icon: Icons.arrow_forward_rounded,
                label: 'View health classification',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HealthClassification(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
