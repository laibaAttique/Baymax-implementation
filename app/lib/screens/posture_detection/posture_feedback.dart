import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../workout_and_exercise/workout_plan.dart';
import '../dashboard/main_navigation.dart';

class PostureFeedbackScreen extends StatefulWidget {
  const PostureFeedbackScreen({Key? key}) : super(key: key);

  @override
  _PostureFeedbackScreenState createState() => _PostureFeedbackScreenState();
}

class _PostureFeedbackScreenState extends State<PostureFeedbackScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _animation = Tween<double>(begin: 0, end: 0.85).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildStatCard(String val, String lbl) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 4)],
        ),
        child: Column(
          children: [
            Text(val, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primary)),
            const SizedBox(height: 2),
            Text(lbl, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackItem(bool isGood, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: isGood ? AppTheme.success.withOpacity(0.2) : Colors.red.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(isGood ? Icons.check : Icons.close, color: isGood ? AppTheme.success : Colors.red, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Summary', style: TextStyle(fontSize: 16)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Column(
                children: [
                  Text('Session Complete! 🎉', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  SizedBox(height: 4),
                  Text('Great job finishing your workout', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                ],
              ),
            ),

            // Score Ring
            SizedBox(
              height: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 140, height: 140,
                    child: AnimatedBuilder(
                      animation: _animation,
                      builder: (context, child) {
                        return CircularProgressIndicator(
                          value: _animation.value,
                          strokeWidth: 10,
                          backgroundColor: AppTheme.border,
                          color: AppTheme.primary,
                        );
                      },
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      return Text('${(_animation.value * 100).toInt()}%', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppTheme.textPrimary));
                    },
                  ),
                ],
              ),
            ),
            const Text('Posture Score', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 24),

            // Rep Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(20)),
              child: const Text('✅ Completed 12 reps', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)), // on primary bg
            ),
            const SizedBox(height: 24),

            // Stats
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildStatCard('12', 'Total Reps'),
                  _buildStatCard('8:30', 'Duration'),
                  _buildStatCard('85%', 'Accuracy'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Feedback List
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Form Feedback', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),
                  _buildFeedbackItem(true, 'Back alignment was maintained'),
                  _buildFeedbackItem(true, 'Knees tracked properly over toes'),
                  _buildFeedbackItem(false, 'Hip depth could be lower in some reps'),
                  _buildFeedbackItem(true, 'Consistent rep speed throughout'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Injury Risk Update
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppTheme.success.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Container(
                    width: 28, height: 28,
                    decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const Icon(Icons.check, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      text: const TextSpan(
                        style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, height: 1.4),
                        children: [
                          TextSpan(text: 'Injury risk remains '),
                          TextSpan(text: 'Low', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                          TextSpan(text: ' — good form consistency!'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const MainNavigation(initialIndex: 2)), // 2 = Workout Tab
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
                child: const Text('Back to Workout Plan'),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const MainNavigation(initialIndex: 3)), // 3 = Analytics Tab
                    (route) => false,
                  );
                },
                child: const Text('View Analytics →', style: TextStyle(color: AppTheme.primary, fontSize: 14)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
