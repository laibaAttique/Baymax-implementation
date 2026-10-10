import 'package:flutter/material.dart';
import '../../models/health_profile.dart';
import '../../theme/app_theme.dart';
import 'step3_fitness_goals.dart';

class Step2MedicalHistory extends StatefulWidget {
  final HealthProfile profile;

  const Step2MedicalHistory({Key? key, required this.profile}) : super(key: key);

  @override
  _Step2MedicalHistoryState createState() => _Step2MedicalHistoryState();
}

class _Step2MedicalHistoryState extends State<Step2MedicalHistory> {
  final List<String> _conditions = ['Diabetes', 'Hypertension', 'Heart Disease', 'Asthma', 'Obesity', 'PCOS', 'None', 'Other'];
  final List<String> _allergies = ['Gluten', 'Dairy', 'Nuts', 'Soy', 'Shellfish', 'Eggs', 'None', 'Other'];
  
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

  void _toggleCondition(String c) {
    setState(() {
      if (_selectedConditions.contains(c)) {
        _selectedConditions.remove(c);
      } else {
        _selectedConditions.add(c);
      }
    });
  }

  void _toggleAllergy(String a) {
    setState(() {
      if (_selectedAllergies.contains(a)) {
        _selectedAllergies.remove(a);
      } else {
        _selectedAllergies.add(a);
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

  Widget _buildChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Baymax')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: Text('Step 2 of 3 — Medical History & Allergies')),
            const SizedBox(height: 24),
            const Text('Medical Conditions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const Text('Select any conditions that apply', style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _conditions.map((c) => _buildChip(c, _selectedConditions.contains(c), () => _toggleCondition(c))).toList(),
            ),
            const SizedBox(height: 32),
            const Text('Food Allergies', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const Text('Select any food allergies', style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allergies.map((a) => _buildChip(a, _selectedAllergies.contains(a), () => _toggleAllergy(a))).toList(),
            ),
            const SizedBox(height: 32),
            const Text('Current Medications (Optional)', style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            TextField(
              controller: _medsController,
              maxLines: 3,
              decoration: const InputDecoration(hintText: "List any medications you're currently taking..."),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.card),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('← Back', style: TextStyle(color: AppTheme.textPrimary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _next,
                    child: const Text('Next: Fitness Goals →'),
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
