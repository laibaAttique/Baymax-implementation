import 'package:flutter/material.dart';
import '../../models/health_profile.dart';
import '../../services/api_client.dart';
import '../../services/profile_service.dart';
import '../../services/user_session.dart';
import '../../utils/health_calc.dart';
import '../../utils/validators.dart';
import '../../theme/app_theme.dart';
import '../../widgets/forms.dart';
import '../../widgets/glass.dart';
import 'bmi_result.dart';

class Step3FitnessGoals extends StatefulWidget {
  final HealthProfile profile;

  const Step3FitnessGoals({Key? key, required this.profile}) : super(key: key);

  @override
  _Step3FitnessGoalsState createState() => _Step3FitnessGoalsState();
}

class _Step3FitnessGoalsState extends State<Step3FitnessGoals> {
  String _primaryGoal = 'Lose Weight';
  String _activityLevel = 'Moderately Active';
  double _workoutFrequency = 4;
  final TextEditingController _targetWeightController = TextEditingController();
  String _targetWeightUnit = 'kg';

  bool _isLoading = false;

  static const List<({IconData icon, String title, String desc})> _goals = [
    (icon: Icons.local_fire_department_rounded, title: 'Lose Weight', desc: 'Burn fat & reduce body weight'),
    (icon: Icons.fitness_center_rounded, title: 'Gain Muscle', desc: 'Build strength & muscle mass'),
    (icon: Icons.balance_rounded, title: 'Maintain & Stay Fit', desc: 'Keep current fitness level'),
  ];

  static const List<({IconData icon, String label, String hint})> _activities = [
    (icon: Icons.weekend_rounded, label: 'Sedentary', hint: 'Little exercise'),
    (icon: Icons.directions_walk_rounded, label: 'Lightly Active', hint: '1-3 days a week'),
    (icon: Icons.directions_run_rounded, label: 'Moderately Active', hint: '3-5 days a week'),
    (icon: Icons.fitness_center_rounded, label: 'Very Active', hint: '6-7 days a week'),
    (icon: Icons.emoji_events_rounded, label: 'Athlete', hint: 'Training twice a day'),
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    if (_goals.any((g) => g.title == p.primaryGoal)) _primaryGoal = p.primaryGoal;
    if (_activities.any((a) => a.label == p.activityLevel)) _activityLevel = p.activityLevel;
    _workoutFrequency = p.workoutFrequency.clamp(2, 6).toDouble();
    if (p.targetWeightValue > 0) {
      _targetWeightController.text = p.targetWeightValue.toString();
      _targetWeightUnit = p.targetWeightUnit;
    }
  }

  bool _targetTouched = false;

  double get _currentKg => HealthCalc.toKg(widget.profile.weightValue, widget.profile.weightUnit);
  double get _heightCm => HealthCalc.toCm(widget.profile.heightValue, widget.profile.heightUnit);

  String? get _targetError =>
      Validators.targetWeight(_targetWeightController.text, _targetWeightUnit, currentKg: _currentKg, heightCm: _heightCm);

  /// Switching kg / lbs converts the number already typed.
  void _switchTargetUnit(String u) {
    final n = double.tryParse(_targetWeightController.text.trim());
    setState(() {
      if (n != null && u != _targetWeightUnit) {
        final v = HealthCalc.fromKg(HealthCalc.toKg(n, _targetWeightUnit), u);
        _targetWeightController.text = v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
      }
      _targetWeightUnit = u;
    });
  }

  Future<void> _completeProfile() async {
    if (_targetError != null) return;
    setState(() => _isLoading = true);

    widget.profile.primaryGoal = _primaryGoal;
    widget.profile.activityLevel = _activityLevel;
    widget.profile.workoutFrequency = _workoutFrequency.toInt();
    widget.profile.targetWeightValue = double.tryParse(_targetWeightController.text) ?? 0;
    widget.profile.targetWeightUnit = _targetWeightUnit;

    String? profileId;
    String? saveError;

    // Module 2: classify first so the result is saved with the profile (FE-5)
    // and the Module 3 plan can be generated immediately.
    await UserSession.instance.setProfile(widget.profile);

    try {
      profileId = await ProfileService.instance.saveMine(widget.profile);
    } on ApiException catch (e) {
      // Keep going with local data so the user still sees their results.
      saveError = e.message;
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (saveError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Your profile could not be saved ($saveError). Try again later.')),
      );
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => BmiResult(profile: widget.profile, profileId: profileId)),
      );
    }
  }

  @override
  void dispose() {
    _targetWeightController.dispose();
    super.dispose();
  }

  Widget _goalCard(({IconData icon, String title, String desc}) g) {
    final isSelected = _primaryGoal == g.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: '${g.title}. ${g.desc}',
        excludeSemantics: true,
        child: Pressable(
          radius: AppTheme.rLarge,
          onTap: () => setState(() => _primaryGoal = g.title),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white.withOpacity(0.92) : AppTheme.card,
              borderRadius: BorderRadius.circular(AppTheme.rLarge),
              border: Border.all(color: isSelected ? AppTheme.primary : Colors.white, width: isSelected ? 2 : 1.2),
              boxShadow: isSelected ? AppTheme.glowShadow(blur: 22, opacity: 0.2, offset: const Offset(0, 8)) : AppTheme.softShadow(),
            ),
            child: Row(
              children: [
                IconWell(icon: g.icon, size: 48, filled: isSelected),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.2)),
                      const SizedBox(height: 2),
                      Text(g.desc, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, key: ValueKey(isSelected), color: isSelected ? AppTheme.primary : AppTheme.border),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _activityCard(({IconData icon, String label, String hint}) a, double width) {
    final isSelected = _activityLevel == a.label;
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        selected: isSelected,
        label: '${a.label}. ${a.hint}',
        excludeSemantics: true,
        child: Pressable(
          radius: AppTheme.rMedium + 2,
          onTap: () => setState(() => _activityLevel = a.label),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryLight : AppTheme.card,
              borderRadius: BorderRadius.circular(AppTheme.rMedium + 2),
              border: Border.all(color: isSelected ? AppTheme.primary : Colors.white, width: isSelected ? 2 : 1.2),
              boxShadow: isSelected ? const [] : AppTheme.softShadow(),
            ),
            child: Row(
              children: [
                Icon(a.icon, size: 24, color: isSelected ? AppTheme.primary : AppTheme.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.label, style: TextStyle(fontSize: 13.5, height: 1.2, color: isSelected ? AppTheme.primary : AppTheme.textPrimary, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(a.hint, style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
              const Reveal(child: StepHeader(step: 3, total: 3, title: 'Goals & activity', subtitle: 'Tell us what you are aiming for and how active you are today.')),
              const SectionHeader('Primary goal', padding: EdgeInsets.fromLTRB(0, 24, 0, 12)),
              for (final g in _goals) _goalCard(g),
              const SectionHeader('Activity level', padding: EdgeInsets.fromLTRB(0, 20, 0, 12)),
              LayoutBuilder(builder: (context, c) {
                final w = (c.maxWidth - 10) / 2;
                return Wrap(spacing: 10, runSpacing: 10, children: [for (final a in _activities) _activityCard(a, w)]);
              }),
              const SectionHeader('Workout frequency', padding: EdgeInsets.fromLTRB(0, 24, 0, 8)),
              GlassCard(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  children: [
                    FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(_workoutFrequency.toInt().toString(), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: AppTheme.primary, letterSpacing: -1.5)),
                        const SizedBox(width: 8),
                        const Text('days per week', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w700)),
                      ],
                    )),
                    Slider(
                      value: _workoutFrequency,
                      min: 1,
                      max: 7,
                      divisions: 6,
                      label: _workoutFrequency.toInt().toString(),
                      onChanged: (val) => setState(() => _workoutFrequency = val),
                    ),
                  ],
                ),
              ),
              const SectionHeader('Target weight (optional)', padding: EdgeInsets.fromLTRB(0, 24, 0, 12)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _targetWeightController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() => _targetTouched = true),
                      decoration: InputDecoration(labelText: 'Target weight', errorText: _targetTouched ? _targetError : null, errorMaxLines: 3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 118,
                    child: PillChoice(options: const ['kg', 'lbs'], selected: _targetWeightUnit, height: 56, onChanged: _switchTargetUnit),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              StepActions(nextLabel: 'Complete my profile', onNext: (_isLoading || _targetError != null) ? null : _completeProfile, onBack: () => Navigator.pop(context), loading: _isLoading),
            ],
          ),
        ),
      ),
    );
  }
}
