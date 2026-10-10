import 'package:flutter/material.dart';
import '../../models/health_profile.dart';
import '../../services/api_client.dart';
import '../../services/profile_service.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';
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

  final List<Map<String, String>> _goals = [
    {'icon': '🔥', 'title': 'Lose Weight', 'desc': 'Burn fat & reduce body weight'},
    {'icon': '💪', 'title': 'Gain Muscle', 'desc': 'Build strength & muscle mass'},
    {'icon': '⚖️', 'title': 'Maintain & Stay Fit', 'desc': 'Keep current fitness level'},
  ];

  final List<Map<String, String>> _activities = [
    {'icon': '🛋️', 'label': 'Sedentary'},
    {'icon': '🚶', 'label': 'Lightly Active'},
    {'icon': '🏃', 'label': 'Moderately Active'},
    {'icon': '🏋️', 'label': 'Very Active'},
    {'icon': '🏅', 'label': 'Athlete'},
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    if (_goals.any((g) => g['title'] == p.primaryGoal)) _primaryGoal = p.primaryGoal;
    if (_activities.any((a) => a['label'] == p.activityLevel)) _activityLevel = p.activityLevel;
    _workoutFrequency = p.workoutFrequency.clamp(2, 6).toDouble();
    if (p.targetWeightValue > 0) {
      _targetWeightController.text = p.targetWeightValue.toString();
      _targetWeightUnit = p.targetWeightUnit;
    }
  }

  Future<void> _completeProfile() async {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Baymax')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: Text('Step 3 of 3 — Fitness Goals & Activity Level')),
            const SizedBox(height: 24),
            
            const Text('Primary Fitness Goal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            ..._goals.map((g) {
              final isSelected = _primaryGoal == g['title'];
              return GestureDetector(
                onTap: () => setState(() => _primaryGoal = g['title']!),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border, width: 2),
                    boxShadow: isSelected ? [BoxShadow(color: AppTheme.primaryLight, blurRadius: 10)] : null,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(color: isSelected ? AppTheme.primary : AppTheme.primaryLight, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text(g['icon']!, style: const TextStyle(fontSize: 22)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g['title']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(g['desc']!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                          ],
                        ),
                      ),
                      if (isSelected) const Icon(Icons.check_circle, color: AppTheme.primary),
                    ],
                  ),
                ),
              );
            }).toList(),
            
            const SizedBox(height: 24),
            const Text('Activity Level', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _activities.map((a) {
                  final isSelected = _activityLevel == a['label'];
                  return GestureDetector(
                    onTap: () => setState(() => _activityLevel = a['label']!),
                    child: Container(
                      width: 110,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primaryLight : AppTheme.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border, width: 2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(a['icon']!, style: const TextStyle(fontSize: 28)),
                          const SizedBox(height: 8),
                          Text(a['label']!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : AppTheme.textSecondary, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            
            const SizedBox(height: 32),
            const Text('Workout Frequency', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Text(_workoutFrequency.toInt().toString(), style: const TextStyle(fontSize: 52, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    const Text('days per week', style: TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ),
            Slider(
              value: _workoutFrequency,
              min: 1,
              max: 7,
              divisions: 6,
              activeColor: AppTheme.primary,
              onChanged: (val) => setState(() => _workoutFrequency = val),
            ),

            const SizedBox(height: 32),
            const Text('Target Weight (Optional)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _targetWeightController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Target Weight'),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    children: ['kg', 'lbs'].map((u) {
                      final isSelected = _targetWeightUnit == u;
                      return GestureDetector(
                        onTap: () => setState(() => _targetWeightUnit = u),
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

            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _completeProfile,
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Complete My Profile ✓'),
            ),
          ],
        ),
      ),
    );
  }
}
