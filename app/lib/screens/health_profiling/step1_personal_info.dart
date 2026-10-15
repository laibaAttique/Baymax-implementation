import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../models/health_profile.dart';
import '../../utils/health_calc.dart';
import '../../utils/validators.dart';
import '../../theme/app_theme.dart';
import '../../widgets/forms.dart';
import '../../widgets/glass.dart';
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

  final Set<String> _touched = {};

  String? get _nameError => _touched.contains('name') ? Validators.fullName(_nameController.text) : null;
  String? get _heightError => _touched.contains('height') ? Validators.height(_heightController.text, _heightUnit) : null;
  String? get _weightError => _touched.contains('weight') ? Validators.weight(_weightController.text, _weightUnit) : null;
  String? get _dobError => _touched.contains('dob') ? Validators.dateOfBirth(_dob) : null;

  /// "Next" is enabled only when every required field is valid (mockup M4, FR4.8).
  bool get _valid =>
      Validators.fullName(_nameController.text) == null &&
      Validators.dateOfBirth(_dob) == null &&
      Validators.height(_heightController.text, _heightUnit) == null &&
      Validators.weight(_weightController.text, _weightUnit) == null;

  /// Switching a unit converts the number already typed, so the value stays the same height or weight (mockup M4, FR4.5).
  void _switchUnit({String? height, String? weight}) {
    String convert(TextEditingController c, String from, String to, double Function(double, String) toBase, double Function(double, String) fromBase, int decimals) {
      final n = double.tryParse(c.text.trim());
      if (n != null && from != to) {
        final v = fromBase(toBase(n, from), to);
        c.text = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(decimals);
      }
      return to;
    }

    setState(() {
      if (height != null) _heightUnit = convert(_heightController, _heightUnit, height, HealthCalc.toCm, HealthCalc.fromCm, 2);
      if (weight != null) _weightUnit = convert(_weightController, _weightUnit, weight, HealthCalc.toKg, HealthCalc.fromKg, 1);
    });
    _calculateBMI();
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
    setState(() {
      _touched.add('dob');
      if (picked != null) _dob = picked;
    });
  }

  String _dobIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _next() {
    final height = double.tryParse(_heightController.text) ?? 0;
    final weight = double.tryParse(_weightController.text) ?? 0;
    final heightCm = HealthCalc.toCm(height, _heightUnit);
    final weightKg = HealthCalc.toKg(weight, _weightUnit);

    if (!_valid) return;

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
  void dispose() {
    _nameController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log out',
            onPressed: () async {
              await AuthService.instance.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const SplashScreen()), (route) => false);
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Reveal(child: StepHeader(step: 1, total: 3, title: 'About you', subtitle: 'Your details are used to work out your BMI, calorie needs and a safe plan.')),
              const SizedBox(height: 22),
              Reveal(
                index: 1,
                child: GlassCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() => _touched.add('name')),
                        decoration: InputDecoration(labelText: 'Full name', prefixIcon: const Icon(Icons.person_outline_rounded), errorText: _nameError),
                      ),
                      const SizedBox(height: 20),
                      const Text('Gender', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 8),
                      PillChoice(options: const ['Male', 'Female', 'Other'], selected: _selectedGender, onChanged: (g) => setState(() => _selectedGender = g)),
                      const SizedBox(height: 20),
                      Semantics(
                        button: true,
                        label: 'Date of birth: ${_dob == null ? 'not selected' : _dobIso(_dob!)}',
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: _pickDob,
                          borderRadius: BorderRadius.circular(AppTheme.rMedium),
                          child: InputDecorator(
                            decoration: InputDecoration(labelText: 'Date of birth', suffixIcon: const Icon(Icons.calendar_month_rounded), errorText: _dobError),
                            child: Text(
                              _dob == null ? 'Select your date of birth' : _dobIso(_dob!),
                              style: TextStyle(color: _dob == null ? AppTheme.textSecondary : AppTheme.textPrimary, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Reveal(
                index: 2,
                child: GlassCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _heightController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (_) => setState(() => _touched.add('height')),
                              decoration: InputDecoration(labelText: 'Height', helperText: _heightUnit == 'ft' ? 'Decimal feet, e.g. 5.5' : null, errorText: _heightError, errorMaxLines: 2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 118,
                            child: PillChoice(
                              options: const ['cm', 'ft'],
                              selected: _heightUnit,
                              height: 56,
                              onChanged: (u) => _switchUnit(height: u),
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
                              onChanged: (_) => setState(() => _touched.add('weight')),
                              decoration: InputDecoration(labelText: 'Weight', errorText: _weightError, errorMaxLines: 2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 118,
                            child: PillChoice(
                              options: const ['kg', 'lbs'],
                              selected: _weightUnit,
                              height: 56,
                              onChanged: (u) => _switchUnit(weight: u),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _bmi > 0
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: AppTheme.heroGradient,
                            borderRadius: BorderRadius.circular(AppTheme.rLarge),
                            boxShadow: AppTheme.glowShadow(blur: 26, opacity: 0.3, offset: const Offset(0, 12)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('YOUR BMI', style: AppTheme.overline.copyWith(color: Colors.white.withOpacity(0.82))),
                                    Text(_bmi.toStringAsFixed(1), style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1.5, height: 1.1)),
                                  ],
                                ),
                              ),
                              Icon(Icons.speed_rounded, size: 44, color: Colors.white.withOpacity(0.5)),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: 26),
              StepActions(nextLabel: 'Next: medical history', onNext: _valid ? _next : null),
            ],
          ),
        ),
      ),
    );
  }
}
