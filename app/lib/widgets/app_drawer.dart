import 'package:flutter/material.dart';
import '../screens/allergy/allergy_scanner.dart';
import '../screens/analytics/body_transform_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/chatbot/chatbot_screen.dart';
import '../screens/community/community_screen.dart';
import '../screens/nutrition/calorie_target_screen.dart';
import '../screens/nutrition/nutrition_plan_screen.dart';
import '../screens/posture_detection/posture_home.dart';
import '../screens/profile/settings_screen.dart';
import '../screens/profile/sources_screen.dart';
import '../screens/specialists/my_appointments_screen.dart';
import '../screens/specialists/specialists_screen.dart';
import '../screens/voice_assistant/voice_assistant_screen.dart';
import '../services/auth_service.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// The menu: every screen of the app is reachable from here. [onSelectTab] switches the bottom navigation tab.
class AppDrawer extends StatelessWidget {
  final ValueChanged<int> onSelectTab;
  const AppDrawer({Key? key, required this.onSelectTab}) : super(key: key);

  Widget _tile(BuildContext context, IconData icon, String label, {VoidCallback? onTap, int? tab, Widget? page, Color color = AppTheme.primary}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Pressable(
        radius: 14,
        onTap: () {
          final navigator = Navigator.of(context);
          navigator.pop(); // close the drawer
          if (tab != null) {
            onSelectTab(tab);
          } else if (page != null) {
            navigator.push(MaterialPageRoute(builder: (_) => page));
          } else {
            onTap?.call();
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(children: [
            IconWell(icon: icon, color: color, size: 36),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppTheme.textPrimary))),
            const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textSecondary),
          ]),
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 20, 6),
        child: Text(text.toUpperCase(), style: AppTheme.overline),
      );

  @override
  Widget build(BuildContext context) {
    final name = UserSession.instance.profile?.fullName.trim() ?? '';
    return Drawer(
      width: 320,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(AppTheme.rHero))),
      child: SafeArea(
        // A plain Column in a scroll view (not a lazy ListView): the menu is short and every entry must exist for screen readers.
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: AppTheme.heroGradient,
                  borderRadius: BorderRadius.circular(AppTheme.rLarge),
                  boxShadow: AppTheme.glowShadow(blur: 22, opacity: 0.30),
                ),
                child: Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.55))),
                    alignment: Alignment.center,
                    child: Text(name.isEmpty ? 'B' : name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Baymax', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.2)),
                      const SizedBox(height: 2),
                      Text(name.isEmpty ? 'Your health companion' : name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.86), fontSize: 13, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ]),
              ),
            ),
            _heading('Main'),
            _tile(context, Icons.home_rounded, 'Home', tab: 0),
            _tile(context, Icons.restaurant_rounded, 'Diet tracker', tab: 1),
            _tile(context, Icons.fitness_center_rounded, 'Workout plan', tab: 2),
            _tile(context, Icons.insights_rounded, 'Analytics', tab: 3),
            _tile(context, Icons.person_rounded, 'Profile', tab: 4),
            _heading('Health'),
            _tile(context, Icons.local_fire_department_rounded, 'Calorie target & weight', page: const CalorieTargetScreen()),
            _tile(context, Icons.set_meal_rounded, 'Nutrition plan', page: const NutritionPlanScreen()),
            _tile(context, Icons.shield_rounded, 'Allergy scanner', page: const AllergyScanner()),
            _tile(context, Icons.self_improvement_rounded, 'Posture check', page: const PostureDetectionHome()),
            _tile(context, Icons.trending_up_rounded, 'Body transformation', page: const BodyTransformScreen()),
            _heading('Community & help'),
            _tile(context, Icons.emoji_events_rounded, 'Progress & leaderboard', page: const CommunityScreen()),
            _tile(context, Icons.auto_awesome_rounded, 'AI chatbot', page: const ChatbotScreen()),
            _tile(context, Icons.mic_rounded, 'Voice assistant', page: const VoiceAssistantScreen()),
            _tile(context, Icons.medical_services_rounded, 'Find a specialist', page: const SpecialistsScreen()),
            _tile(context, Icons.event_note_rounded, 'My appointments', page: const MyAppointmentsScreen()),
            _heading('App'),
            _tile(context, Icons.notifications_active_rounded, 'Reminders & community settings', page: const SettingsScreen()),
            _tile(context, Icons.menu_book_rounded, 'Sources & methodology', page: const SourcesScreen()),
            _tile(context, Icons.logout_rounded, 'Log out', color: AppTheme.error, onTap: () async {
              final navigator = Navigator.of(context);
              await AuthService.instance.signOut();
              navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const SplashScreen()), (r) => false);
            }),
            ],
          ),
        ),
      ),
    );
  }
}
