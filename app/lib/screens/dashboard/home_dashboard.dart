import 'package:flutter/material.dart';
import '../../models/plan.dart';
import '../../services/auth_service.dart';
import '../../services/food_log_service.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';
import '../allergy/allergy_scanner.dart';
import '../auth/splash_screen.dart';
import '../chatbot/chatbot_screen.dart';
import '../posture_detection/posture_mode.dart';

class HomeDashboard extends StatefulWidget {
  final Function(int) onNavigateTab;
  const HomeDashboard({Key? key, required this.onNavigateTab}) : super(key: key);

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  double _eatenToday = 0;

  @override
  void initState() {
    super.initState();
    _loadIntake();
    FoodLogService.instance.changes.addListener(_loadIntake);
  }

  @override
  void dispose() {
    FoodLogService.instance.changes.removeListener(_loadIntake);
    super.dispose();
  }

  Future<void> _loadIntake() async {
    try {
      final entries = await FoodLogService.instance.forDate(FoodLogService.dateKey(DateTime.now()));
      if (mounted) setState(() => _eatenToday = FoodLogService.totalKcal(entries));
    } catch (_) {
      // Leave the last known value; the Diet tab shows the error details.
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good Morning' : (h < 17 ? 'Good Afternoon' : 'Good Evening');
  }

  Widget _buildStatCard(String icon, String value, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickTile(BuildContext context, String icon, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap ??
          () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${label.replaceAll('\n', ' ')} is coming soon!'), behavior: SnackBarBehavior.floating),
            );
          },
      child: Container(
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _workoutCard(PersonalizedPlan? plan, double weightKg) {
    final today = plan?.workoutFor(DateTime.now());
    final String title;
    final String subtitle;
    if (plan == null) {
      title = 'No plan yet';
      subtitle = 'Complete your health profile';
    } else if (today == null) {
      title = 'Rest day';
      subtitle = '🛌 Recover, stretch and hydrate';
    } else {
      title = today.name;
      subtitle = '⏱️ ${today.durationMin} min  ·  🔥 ${today.kcal(weightKg)} kcal';
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppTheme.primaryLight, Color(0xFFA8D5BA)]),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(today == null && plan != null ? '🛌' : '🏋️', style: const TextStyle(fontSize: 28)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("TODAY'S WORKOUT", style: TextStyle(fontSize: 10, letterSpacing: 1, color: AppTheme.textSecondary)),
                const SizedBox(height: 2),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => widget.onNavigateTab(2),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Go ›', style: TextStyle(fontSize: 12)),
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
        final profile = session.profile;
        final plan = session.plan;
        final firstName = (profile?.fullName.trim().isNotEmpty ?? false) ? profile!.fullName.trim().split(' ').first : '';
        final target = plan?.nutrition.targetKcal;
        final today = plan?.workoutFor(DateTime.now());

        return Scaffold(
          appBar: AppBar(
            title: const Text('Baymax', style: TextStyle(fontSize: 16)),
            centerTitle: true,
            leading: const Padding(padding: EdgeInsets.all(12.0), child: Icon(Icons.menu)),
            actions: [
              IconButton(icon: const Icon(Icons.notifications_none), onPressed: () {}),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Log Out',
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await AuthService.instance.signOut();
                  navigator.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const SplashScreen()),
                    (route) => false,
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.primaryLight,
                  child: Text(
                    firstName.isEmpty ? '?' : firstName[0].toUpperCase(),
                    style: const TextStyle(color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_greeting()}${firstName.isEmpty ? '' : ', $firstName'} 👋',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(height: 4),
                      const Text("Let's crush your fitness goals today!", style: TextStyle(color: AppTheme.textSecondary)),
                    ],
                  ),
                ),

                // Stats
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      _buildStatCard('🍽️', '${_eatenToday.round()}', 'Calories Eaten'),
                      _buildStatCard('🎯', target == null ? '—' : '$target', 'Daily Target'),
                      _buildStatCard('⏱️', today == null ? '0' : '${today.durationMin}', 'Planned Workout Min'),
                    ],
                  ),
                ),

                _workoutCard(plan, profile?.weightKg ?? 70),

                // Emotion Banner (Module 6 - later phase)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('How are you feeling today?', style: TextStyle(fontWeight: FontWeight.w500, color: AppTheme.textSecondary, fontSize: 13)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: ['😊', '😐', '😢', '😤', '😰'].map((emoji) {
                          return Container(
                            width: 46,
                            height: 46,
                            decoration: const BoxDecoration(color: AppTheme.background, shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: Text(emoji, style: const TextStyle(fontSize: 22)),
                          );
                        }).toList(),
                      )
                    ],
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.only(left: 20, top: 12, bottom: 8),
                  child: Text('Quick Access', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.85,
                    children: [
                      _buildQuickTile(context, '💪', 'Workout\nPlan', onTap: () => widget.onNavigateTab(2)),
                      _buildQuickTile(context, '🥗', 'Diet\nTracker', onTap: () => widget.onNavigateTab(1)),
                      _buildQuickTile(context, '🧘', 'Posture\nCheck',
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PostureModeSelection()))),
                      _buildQuickTile(context, '📊', 'Body\nTransform'),
                      _buildQuickTile(context, '🏆', 'Leader\nboard'),
                      _buildQuickTile(context, '🛡️', 'Allergy\nScanner',
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AllergyScanner()))),
                      _buildQuickTile(context, '🤖', 'AI\nChatbot',
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatbotScreen()))),
                      _buildQuickTile(context, '👩‍⚕️', 'Find\nSpecialist'),
                    ],
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        );
      },
    );
  }
}
