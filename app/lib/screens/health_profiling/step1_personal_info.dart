import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../models/health_profile.dart';
import '../../utils/health_calc.dart';
import '../../theme/app_theme.dart';
import 'step2_medical_history.dart';
import '../auth/splash_screen.dart';

class Step1PersonalInfo extends StatefulWidget {
  final HealthProfile profile;

  const Step1PersonalInfo({Key? key, required this.profile}) : super(key: key);

  @override
  _Step1PersonalInfoState createState() => _Step1PersonalInfoState();
}

class _Step1PersonalInfoState extends State<Step1PersonalInfo> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  
  String _selectedGender = 'Female';
  String _heightUnit = 'cm';
  String _weightUnit = 'kg';
  DateTime? _dob;
  double _bmi = 0;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.profile.fullName;
    _dob = DateTime.tryParse(widget.profile.dob);
    if (widget.profile.gender.isNotEmpty) _selectedGender = widget.profile.gender;
    _heightUnit = widget.profile.heightUnit;
    _weightUnit = widget.profile.weightUnit;
    if (widget.profile.heightValue > 0) _heightController.text = widget.profile.heightValue.toString();
    if (widget.profile.weightValue > 0) _weightController.text = widget.profile.weightValue.toString();
    _heightController.addListener(_calculateBMI);
    _weightController.addListener(_calculateBMI);
  }

  void _calculateBMI() {
    final h = HealthCalc.toCm(double.tryParse(_heightController.text) ?? 0, _heightUnit);
    final w = HealthCalc.toKg(double.tryParse(_weightController.text) ?? 0, _weightUnit);
    setState(() => _bmi = HealthCalc.bmi(w, h));
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 13, now.month, now.day),
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  String _dobIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _next() {
    final height = double.tryParse(_heightController.text) ?? 0;
    final weight = double.tryParse(_weightController.text) ?? 0;
    final heightCm = HealthCalc.toCm(height, _heightUnit);
    final weightKg = HealthCalc.toKg(weight, _weightUnit);

    String? error;
    if (_nameController.text.trim().isEmpty) {
      error = 'Please enter your full name';
    } else if (_dob == null) {
      error = 'Please select your date of birth';
    } else if (heightCm < 100 || heightCm > 250) {
      error = _heightUnit == 'ft' ? 'Enter your height in feet, e.g. 5.5' : 'Enter a height between 100 and 250 cm';
    } else if (weightKg < 25 || weightKg > 300) {
      error = 'Enter a realistic weight';
    }
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    widget.profile.fullName = _nameController.text.trim();
    widget.profile.dob = _dobIso(_dob!);
    widget.profile.gender = _selectedGender;
    widget.profile.heightValue = height;
    widget.profile.heightUnit = _heightUnit;
    widget.profile.weightValue = weight;
    widget.profile.weightUnit = _weightUnit;
    widget.profile.calculatedBMI = HealthCalc.bmi(weightKg, heightCm);

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => Step2MedicalHistory(profile: widget.profile)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Baymax'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log Out',
            onPressed: () async {
              await AuthService.instance.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const SplashScreen()),
                  (route) => false,
                );
              }
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: Text('Step 1 of 3 — Personal Information')),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 16),
            const Text('Gender', style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            Row(
              children: ['Male', 'Female', 'Other'].map((g) {
                final isSelected = _selectedGender == g;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedGender = g),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primary : AppTheme.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isSelected ? AppTheme.primary : Colors.transparent),
                      ),
                      alignment: Alignment.center,
                      child: Text(g, style: TextStyle(color: isSelected ? Colors.white : AppTheme.textPrimary)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _pickDob,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date of Birth', suffixIcon: Icon(Icons.calendar_today, size: 18)),
                child: Text(
                  _dob == null ? 'Select your date of birth' : _dobIso(_dob!),
                  style: TextStyle(color: _dob == null ? AppTheme.textSecondary : AppTheme.textPrimary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _heightController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Height', helperText: _heightUnit == 'ft' ? 'Decimal feet, e.g. 5.5' : null),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    children: ['cm', 'ft'].map((u) {
                      final isSelected = _heightUnit == u;
                      return GestureDetector(
                        onTap: () => setState(() { _heightUnit = u; _calculateBMI(); }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(u, style: TextStyle(color: isSelected ? Colors.white : AppTheme.textSecondary)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _weightController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Weight'),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    children: ['kg', 'lbs'].map((u) {
                      final isSelected = _weightUnit == u;
                      return GestureDetector(
                        onTap: () => setState(() { _weightUnit = u; _calculateBMI(); }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(u, style: TextStyle(color: isSelected ? Colors.white : AppTheme.textSecondary)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_bmi > 0)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(20),
                  border: const Border(left: BorderSide(color: AppTheme.primary, width: 4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('YOUR BMI', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    Text(_bmi.toStringAsFixed(1), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  ],
                ),
              ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _next,
              child: const Text('Next: Medical History →'),
            ),
          ],
        ),
      ),
    );
  }
}
