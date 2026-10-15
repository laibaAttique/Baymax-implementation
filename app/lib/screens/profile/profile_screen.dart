import 'package:flutter/material.dart';
import '../../models/health_profile.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../auth/splash_screen.dart';
import '../health_profiling/health_classification.dart';
import '../health_profiling/step1_personal_info.dart';
import '../community/community_screen.dart';
import 'settings_screen.dart';
import '../nutrition/calorie_target_screen.dart';
import '../../services/gamification.dart' show UserRole, UserRoleRules;
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

  Widget _section(String title, IconData icon, List<(String, String)> rows, int index) {
    return Reveal(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                IconWell(icon: icon, size: 34),
                const SizedBox(width: 12),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary, letterSpacing: -0.2)),
              ]),
              const SizedBox(height: 10),
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(color: AppTheme.border.withOpacity(0.6)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 4, child: Text(rows[i].$1, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w500))),
                      Expanded(
                        flex: 6,
                        child: Text(rows[i].$2, textAlign: TextAlign.right, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.3)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuRow(IconData icon, String label, VoidCallback onTap, {Color color = AppTheme.primary, bool last = false}) {
    return Column(
      children: [
        Pressable(
          radius: 14,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(children: [
              IconWell(icon: icon, color: color, size: 38),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: color == AppTheme.error ? AppTheme.error : AppTheme.textPrimary))),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
            ]),
          ),
        ),
        if (!last) Divider(color: AppTheme.border.withOpacity(0.6), indent: 56),
      ],
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
            title: const Text('Profile'),
            actions: [
              IconButton(
                tooltip: 'Refresh from database',
                icon: _refreshing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded),
                onPressed: _refreshing ? null : _refresh,
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: p == null || cls == null || plan == null
              ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No profile found. Complete health profiling first.', textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, AppTheme.navSpace(context)),
                    children: [
                      Reveal(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: AppTheme.heroGradient,
                            borderRadius: BorderRadius.circular(AppTheme.rHero),
                            boxShadow: AppTheme.glowShadow(blur: 30, opacity: 0.32, offset: const Offset(0, 14)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5)),
                                alignment: Alignment.center,
                                child: Text(p.fullName.isEmpty ? '?' : p.fullName[0].toUpperCase(), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white)),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.fullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.4, height: 1.2)),
                                    if (email.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.86), fontSize: 13, fontWeight: FontWeight.w500)),
                                    ],
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                                      child: Text('${cls.category} · ${cls.riskLevel} risk',
                                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: HealthClassification.colorFor(cls.riskLevel))),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (session.role != UserRole.user)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Center(child: InfoChip('Role: ${session.role.label}', icon: Icons.badge_rounded)),
                        ),
                      const SizedBox(height: 16),
                      _section('Body', Icons.accessibility_new_rounded, [
                        ('Age', p.age == null ? 'Not set' : '${p.age} years'),
                        ('Gender', p.gender.isEmpty ? '—' : p.gender),
                        ('Height', '${_fmtNum(p.heightValue)} ${p.heightUnit}'),
                        ('Weight', '${_fmtNum(p.weightValue)} ${p.weightUnit}'),
                        ('BMI', '${p.bmi.toStringAsFixed(1)} (${p.bmiCategory})'),
                      ], 1),
                      _section('Goals', Icons.flag_rounded, [
                        ('Primary goal', p.primaryGoal.isEmpty ? '—' : p.primaryGoal),
                        ('Activity level', p.activityLevel.isEmpty ? '—' : p.activityLevel),
                        ('Workouts per week', '${p.workoutFrequency}'),
                        if (p.targetWeightValue > 0) ('Target weight', '${_fmtNum(p.targetWeightValue)} ${p.targetWeightUnit}'),
                      ], 2),
                      _section('Health', Icons.favorite_rounded, [
                        ('Medical conditions', p.medicalConditions.isEmpty ? 'None' : p.medicalConditions.join(', ')),
                        ('Food allergies', p.allergies.isEmpty ? 'None' : p.allergies.join(', ')),
                        if (p.medications.trim().isNotEmpty) ('Medications', p.medications),
                      ], 3),
                      _section('Your targets', Icons.track_changes_rounded, [
                        ('BMR', '${p.bmr.round()} kcal/day'),
                        ('Daily energy use', '${p.tdee.round()} kcal/day'),
                        ('Calorie target', '${plan.nutrition.targetKcal} kcal/day'),
                        ('Protein / carbs / fat', '${plan.nutrition.proteinG} g / ${plan.nutrition.carbsG} g / ${plan.nutrition.fatG} g'),
                        ('Workout days', '${plan.workoutDays} per week · ${plan.intensity} intensity'),
                      ], 4),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
                        child: Text('Data is loaded from your account in the Firebase Realtime Database. Pull down to refresh.',
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4)),
                      ),
                      GlowButton(
                        icon: Icons.edit_rounded,
                        label: 'Update my details',
                        onPressed: () => Navigator.push(
                          context,
                          // A copy, so cancelling halfway leaves the saved profile untouched.
                          MaterialPageRoute(builder: (_) => Step1PersonalInfo(profile: HealthProfile.fromJson(p.toJson()))),
                        ),
                      ),
                      const SizedBox(height: 16),
                      GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Column(
                          children: [
                            _menuRow(Icons.monitor_weight_rounded, 'Calorie target & weight check-in', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalorieTargetScreen()))),
                            _menuRow(Icons.emoji_events_rounded, 'Community & progress', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityScreen())), color: AppTheme.warning),
                            _menuRow(Icons.notifications_active_rounded, 'Reminders & community settings', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
                            _menuRow(Icons.menu_book_rounded, 'Sources & methodology', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SourcesScreen())), color: AppTheme.teal),
                            _menuRow(Icons.logout_rounded, 'Log out', _logout, color: AppTheme.error, last: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
