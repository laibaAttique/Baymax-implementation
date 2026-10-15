import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/glass.dart';
import '../chatbot/chatbot_screen.dart';
import 'home_dashboard.dart';
import '../analytics/analytics_screen.dart';
import '../workout_and_exercise/workout_plan.dart';
import '../diet/diet_tracker.dart';
import '../profile/profile_screen.dart';

class MainNavigation extends StatefulWidget {
  final int initialIndex;
  const MainNavigation({Key? key, this.initialIndex = 0}) : super(key: key);

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> with SingleTickerProviderStateMixin {
  late int _currentIndex;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 300), value: 1);
  late final Animation<double> _fadeCurve = CurvedAnimation(parent: _fade, curve: Curves.easeOutCubic);

  static const _items = [
    NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
    NavItem(Icons.restaurant_outlined, Icons.restaurant_rounded, 'Diet'),
    NavItem(Icons.fitness_center_outlined, Icons.fitness_center_rounded, 'Workout'),
    NavItem(Icons.insights_outlined, Icons.insights_rounded, 'Analytics'),
    NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _onNavigateTab(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    _fade.forward(from: 0); // the new tab fades and rises in; tab state is kept (IndexedStack)
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeDashboard(onNavigateTab: _onNavigateTab, onOpenMenu: () => _scaffoldKey.currentState?.openDrawer()),
      const DietTracker(),
      const WorkoutPlan(),
      const AnalyticsScreen(),
      const ProfileScreen(),
    ];
    final reduce = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      key: _scaffoldKey,
      extendBody: true, // content scrolls under the floating bar
      drawer: AppDrawer(onSelectTab: _onNavigateTab),
      body: AnimatedBuilder(
        animation: _fadeCurve,
        child: IndexedStack(index: _currentIndex, children: pages),
        builder: (context, child) => reduce
            ? child!
            : Opacity(opacity: _fadeCurve.value, child: Transform.translate(offset: Offset(0, 10 * (1 - _fadeCurve.value)), child: child)),
      ),
      // Module 3 FR-6: a floating chat button on Home. It sits above the navigation bar, and Home leaves room under its last row.
      floatingActionButton: _currentIndex != 0
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: 8 + (MediaQuery.paddingOf(context).bottom - MediaQuery.viewPaddingOf(context).bottom)),
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: AppTheme.buttonGradient, borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.glowShadow(blur: 22, opacity: 0.38, offset: const Offset(0, 8))),
                child: Pressable(
                  radius: 20,
                  semanticLabel: 'Open the AI chatbot',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatbotScreen()));
                  },
                  child: const SizedBox(width: 58, height: 58, child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26)),
                ),
              ),
            ),
      bottomNavigationBar: GlassNavBar(currentIndex: _currentIndex, onTap: _onNavigateTab, items: _items),
    );
  }
}
