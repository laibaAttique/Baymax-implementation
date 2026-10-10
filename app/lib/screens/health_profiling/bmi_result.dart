import 'package:flutter/material.dart';
import '../../models/health_profile.dart';
import '../../theme/app_theme.dart';
import 'health_classification.dart';

/// Module 1 results: BMI (FE-6), BMR (FE-7) and daily calories (FE-8),
/// all computed from the profile the user just entered.
class BmiResult extends StatefulWidget {
  final HealthProfile profile;
  final String? profileId;

  const BmiResult({Key? key, required this.profile, this.profileId}) : super(key: key);

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
    if (bmi < 18.5) return Colors.blue;
    if (bmi < 25) return AppTheme.success;
    if (bmi < 30) return AppTheme.warning;
    return AppTheme.error;
  }

  String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  Widget _buildCaloriePill(String title, int kcal) {
    final isSelected = _selected == title;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selected = title),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : AppTheme.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(title, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : AppTheme.textSecondary)),
              const SizedBox(height: 4),
              Text(_fmt(kcal), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : AppTheme.textPrimary)),
            ],
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

    return Scaffold(
      appBar: AppBar(title: const Text('Baymax')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.check_circle, color: AppTheme.success, size: 72),
            const SizedBox(height: 12),
            const Text('Health Profile Complete!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 24),

            // BMI Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(24)),
              child: Column(
                children: [
                  const Text('YOUR BMI', style: TextStyle(color: AppTheme.textSecondary, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Text(bmi.toStringAsFixed(1), style: const TextStyle(fontSize: 52, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(color: _categoryColor(bmi), borderRadius: BorderRadius.circular(20)),
                    child: Text(p.bmiCategory, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(builder: (context, c) {
                    return SizedBox(
                      height: 14,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Container(height: 8, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(4))),
                          Positioned(
                            left: (c.maxWidth - 14) * markerFraction,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Under', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                      Text('Normal', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                      Text('Over', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                      Text('Obese', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // BMR Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(24)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('BASAL METABOLIC RATE', style: TextStyle(color: AppTheme.textSecondary, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_fmt(p.bmr.round()), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(width: 8),
                      const Flexible(
                        child: Padding(padding: EdgeInsets.only(bottom: 6), child: Text('kcal/day', style: TextStyle(color: AppTheme.textSecondary))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Mifflin-St Jeor equation · with ${p.activityLevel.toLowerCase()} activity you burn about ${_fmt(p.tdee.round())} kcal/day',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  if (p.age == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Age assumed to be 30 — add your date of birth for a precise value.', style: TextStyle(fontSize: 12, color: AppTheme.warning)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Calorie Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(24),
                border: const Border(left: BorderSide(color: AppTheme.primary, width: 4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('RECOMMENDED DAILY INTAKE', style: TextStyle(color: AppTheme.textSecondary, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Text('${_fmt(selectedKcal)} kcal', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppTheme.primary)),
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
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(targets.safetyNote!, style: const TextStyle(fontSize: 12, color: AppTheme.warning)),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const HealthClassification()),
                );
              },
              child: const Text('View Health Classification →'),
            ),
          ],
        ),
      ),
    );
  }
}
