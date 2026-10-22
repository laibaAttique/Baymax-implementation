import 'package:flutter/material.dart';
import '../../models/health_profile.dart';
import '../../theme/app_theme.dart';
import '../../widgets/forms.dart';
import '../../widgets/glass.dart';
import 'step3_fitness_goals.dart';

class Step2MedicalHistory extends StatefulWidget {
  final HealthProfile profile;

  const Step2MedicalHistory({Key? key, required this.profile}) : super(key: key);

  @override
  _Step2MedicalHistoryState createState() => _Step2MedicalHistoryState();
}

class _Step2MedicalHistoryState extends State<Step2MedicalHistory> {
  final List<String> _conditions = ['Diabetes', 'Hypertension', 'Heart Disease', 'Asthma', 'Obesity', 'PCOS', 'None', 'Other'];
  final List<String> _allergies = ['Gluten', 'Dairy', 'Nuts', 'Peanuts', 'Soy', 'Shellfish', 'Fish', 'Eggs', 'Sesame', 'None', 'Other'];
  
  final List<String> _selectedConditions = [];
  final List<String> _selectedAllergies = [];
  final TextEditingController _medsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedConditions.addAll(widget.profile.medicalConditions);
    _selectedAllergies.addAll(widget.profile.foodAllergies);
    _medsController.text = widget.profile.medications;
  }

  /// "None" is exclusive: choosing it clears the others, and choosing anything else clears it.
  void _toggle(List<String> list, String item) {
    setState(() {
      if (list.contains(item)) {
        list.remove(item);
      } else {
        if (item == 'None') {
          list.clear();
        } else {
          list.remove('None');
        }
        list.add(item);
      }
    });
  }

  void _next() {
    widget.profile.medicalConditions = _selectedConditions;
    widget.profile.foodAllergies = _selectedAllergies;
    widget.profile.medications = _medsController.text;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => Step3FitnessGoals(profile: widget.profile)),
    );
  }

  @override
  void dispose() {
    _medsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Reveal(
                child: StepHeader(
                  step: 2,
                  total: 3,
                  title: 'Health & allergies',
                  subtitle: 'Conditions you report always take priority when your plan is built, so your workouts and meals stay safe.',
                ),
              ),
              const SizedBox(height: 22),
              Reveal(
                index: 1,
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        IconWell(icon: Icons.favorite_rounded, size: 36),
                        SizedBox(width: 12),
                        Expanded(child: Text('Medical conditions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.3))),
                      ]),
                      const SizedBox(height: 6),
                      const Padding(padding: EdgeInsets.only(left: 48), child: Text('Select any that apply', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w500))),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [for (final c in _conditions) SelectChip(label: c, selected: _selectedConditions.contains(c), onTap: () => _toggle(_selectedConditions, c))],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Reveal(
                index: 2,
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        IconWell(icon: Icons.no_food_rounded, color: AppTheme.error, size: 36),
                        SizedBox(width: 12),
                        Expanded(child: Text('Food allergies', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.3))),
                      ]),
                      const SizedBox(height: 6),
                      const Padding(padding: EdgeInsets.only(left: 48), child: Text('Used to warn you about foods and labels', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w500))),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [for (final a in _allergies) SelectChip(label: a, selected: _selectedAllergies.contains(a), onTap: () => _toggle(_selectedAllergies, a))],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Reveal(
                index: 3,
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Current medications (optional)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _medsController,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(hintText: "List any medications you're currently taking…"),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Mockup M5 FR5.4: a permanent privacy notice. It says only what is true: the app adds no encryption layer of its own.
              const Reveal(
                index: 4,
                child: GlassCard(
                  tint: Color(0xFFEAF6F4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconWell(icon: Icons.lock_rounded, color: AppTheme.teal, size: 38),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your health details are sent over an encrypted connection and stored on Google\'s servers, which encrypt stored data (AES-256 by default). '
                          'Only your signed-in account can read them, and Baymax does not show them to other users.',
                          style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, height: 1.45, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 26),
              StepActions(nextLabel: 'Next: fitness goals', onNext: _next, onBack: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }
}
