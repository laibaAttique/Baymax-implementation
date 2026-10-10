import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'home_dashboard.dart';
import '../workout_and_exercise/workout_plan.dart';
import '../chatbot/chatbot_screen.dart';
import '../diet/diet_tracker.dart';
import '../profile/profile_screen.dart';

class MainNavigation extends StatefulWidget {
  final int initialIndex;
  const MainNavigation({Key? key, this.initialIndex = 0}) : super(key: key);

  @override
  _MainNavigationState createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onNavigateTab(int index) {
    setState(() => _currentIndex = index);
  }

  Widget _buildPlaceholder(String title) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.construction_rounded, size: 64, color: AppTheme.border),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          const Text('Coming Soon', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomeDashboard(onNavigateTab: _onNavigateTab),
      const DietTracker(),
      const WorkoutPlan(),
      _buildPlaceholder('Analytics'),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      // The Diet tab has its own "Log Food" button in the same corner.
      floatingActionButton: _currentIndex == 1 ? null : FloatingActionButton(
        heroTag: 'chatbot',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatbotScreen())),
        backgroundColor: AppTheme.primary,
        child: const Text('💬', style: TextStyle(fontSize: 24)),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onNavigateTab,
          backgroundColor: AppTheme.background,
          selectedItemColor: AppTheme.primary,
          unselectedItemColor: AppTheme.textSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(icon: Text('🏠', style: TextStyle(fontSize: 20)), label: 'Home'),
            BottomNavigationBarItem(icon: Text('🍴', style: TextStyle(fontSize: 20)), label: 'Diet'),
            BottomNavigationBarItem(icon: Text('🏋️', style: TextStyle(fontSize: 20)), label: 'Workout'),
            BottomNavigationBarItem(icon: Text('📈', style: TextStyle(fontSize: 20)), label: 'Analytics'),
            BottomNavigationBarItem(icon: Text('👤', style: TextStyle(fontSize: 20)), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
