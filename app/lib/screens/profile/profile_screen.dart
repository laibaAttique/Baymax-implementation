import 'package:flutter/material.dart';
import '../../models/health_profile.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';
import '../auth/splash_screen.dart';
import '../health_profiling/health_classification.dart';
import '../health_profiling/step1_personal_info.dart';
import 'sources_screen.dart';

/// Shows the signed-in user's real data as stored in the Realtime Database
/// (`users/{uid}/profile`) plus the values derived from it.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await UserSession.instance.load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    await AuthService.instance.signOut();
    navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const SplashScreen()), (r) => false);
  }

  String _fmtNum(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Widget _section(String title, List<(String, String)> rows) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: Text(r.$1, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
                  Expanded(
                    flex: 6,
                    child: Text(r.$2, textAlign: TextAlign.right, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserSession.instance,
      builder: (context, _) {
        final session = UserSession.instance;
        final p = session.profile;
        final cls = session.classification;
        final plan = session.plan;
        final email = AuthService.instance.currentUser?.email ?? '';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Profile', style: TextStyle(fontSize: 16)),
            actions: [
              IconButton(
                tooltip: 'Refresh from database',
                icon: _refreshing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                onPressed: _refreshing ? null : _refresh,
              ),
            ],
          ),
          body: p == null || cls == null || plan == null
              ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No profile found. Complete health profiling first.', textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Center(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: AppTheme.primaryLight,
                              child: Text(
                                p.fullName.isEmpty ? '?' : p.fullName[0].toUpperCase(),
                                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppTheme.primary),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(p.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                            if (email.isNotEmpty) Text(email, style: const TextStyle(color: AppTheme.textSecondary)),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: HealthClassification.colorFor(cls.riskLevel).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${cls.category} · ${cls.riskLevel} risk',
                                style: TextStyle(fontWeight: FontWeight.bold, color: HealthClassification.colorFor(cls.riskLevel)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _section('Body', [
                        ('Age', p.age == null ? 'Not set' : '${p.age} years'),
                        ('Gender', p.gender.isEmpty ? '—' : p.gender),
                        ('Height', '${_fmtNum(p.heightValue)} ${p.heightUnit}'),
                        ('Weight', '${_fmtNum(p.weightValue)} ${p.weightUnit}'),
                        ('BMI', '${p.bmi.toStringAsFixed(1)} (${p.bmiCategory})'),
                      ]),
                      _section('Goals', [
                        ('Primary goal', p.primaryGoal.isEmpty ? '—' : p.primaryGoal),
                        ('Activity level', p.activityLevel.isEmpty ? '—' : p.activityLevel),
                        ('Workouts per week', '${p.workoutFrequency}'),
                        if (p.targetWeightValue > 0) ('Target weight', '${_fmtNum(p.targetWeightValue)} ${p.targetWeightUnit}'),
                      ]),
                      _section('Health', [
                        ('Medical conditions', p.medicalConditions.isEmpty ? 'None' : p.medicalConditions.join(', ')),
                        ('Food allergies', p.allergies.isEmpty ? 'None' : p.allergies.join(', ')),
                        if (p.medications.trim().isNotEmpty) ('Medications', p.medications),
                      ]),
                      _section('Your targets', [
                        ('BMR', '${p.bmr.round()} kcal/day'),
                        ('Daily energy use', '${p.tdee.round()} kcal/day'),
                        ('Calorie target', '${plan.nutrition.targetKcal} kcal/day'),
                        ('Protein / carbs / fat', '${plan.nutrition.proteinG} g / ${plan.nutrition.carbsG} g / ${plan.nutrition.fatG} g'),
                        ('Workout days', '${plan.workoutDays} per week · ${plan.intensity} intensity'),
                      ]),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text('Data is loaded from your account in the Firebase Realtime Database. Pull down to refresh.',
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          // A copy, so cancelling halfway leaves the saved profile untouched.
                          MaterialPageRoute(builder: (_) => Step1PersonalInfo(profile: HealthProfile.fromJson(p.toJson()))),
                        ),
                        icon: const Icon(Icons.edit),
                        label: const Text('Update my details'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SourcesScreen())),
                        icon: const Icon(Icons.menu_book_outlined),
                        label: const Text('Sources & methodology'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout), label: const Text('Log Out')),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
