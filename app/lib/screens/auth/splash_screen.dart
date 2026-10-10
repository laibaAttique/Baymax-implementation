import 'package:flutter/material.dart';
import '../../services/auth_flow.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../test.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _showOnboarding = false;

  final List<Map<String, String>> _slides = [
    {
      'icon': '🏥',
      'title': 'Know Your Health Risk',
      'desc': 'AI-powered health classification based on your BMI, medical history, and fitness data.'
    },
    {
      'icon': '🧘',
      'title': 'Real-Time Posture Correction',
      'desc': 'Computer vision detects and corrects your exercise form in real-time, preventing injuries.'
    },
    {
      'icon': '🥗',
      'title': 'Smart Nutrition for You',
      'desc': 'Intelligent calorie tracking, allergen detection, and personalized meal plans.'
    },
  ];

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
      // Returning user with a saved session: skip onboarding/login.
      if (await AuthService.instance.isSignedIn()) {
        if (mounted) await AuthFlow.continueAfterAuth(context);
        return;
      }
      if (mounted) {
        setState(() => _showOnboarding = true);
        _startAutoPlay();
      }
    });
  }

  void _startAutoPlay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _showOnboarding) {
        if (_currentPage < _slides.length - 1) {
          _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
        } else {
          _pageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
        }
        _startAutoPlay();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Onboarding Content
          if (_showOnboarding)
            SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                // Header
                Column(
                  children: [
                    GestureDetector(
                      // TEMPORARY: long-press the logo to open the Test screen.
                      onLongPress: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TestScreen())),
                      child: Container(
                      width: 80, height: 80,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [AppTheme.primary, Color(0xFF5BAE7A)]),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Text('🤖', style: TextStyle(fontSize: 36)),
                    ),
                    ),
                    const SizedBox(height: 12),
                    const Text('BAYMAX', style: TextStyle(color: AppTheme.primary, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    const SizedBox(height: 24),
                    const Text('Your AI Fitness\nCompanion', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, height: 1.2, color: AppTheme.textPrimary)),
                    const SizedBox(height: 8),
                    const Text('Personalized. Smart. Safe.', style: TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
                const SizedBox(height: 32),
                
                // Carousel
                SizedBox(
                  height: 260,
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (idx) => setState(() => _currentPage = idx),
                    itemCount: _slides.length,
                    itemBuilder: (context, index) {
                      final slide = _slides[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          children: [
                            Container(
                              width: 120, height: 120,
                              decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(24)),
                              alignment: Alignment.center,
                              child: Text(slide['icon']!, style: const TextStyle(fontSize: 48)),
                            ),
                            const SizedBox(height: 20),
                            Text(slide['title']!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                            const SizedBox(height: 8),
                            Text(slide['desc']!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                
                // Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_slides.length, (index) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPage == index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index ? AppTheme.primary : AppTheme.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 32),
                
                // Actions
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    children: [
                      ElevatedButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupScreen())),
                        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text('Get Started'), SizedBox(width: 8), Icon(Icons.arrow_forward, size: 18)]),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Already have an account? ', style: TextStyle(color: AppTheme.textSecondary)),
                          GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                            child: const Text('Log In', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Initial Splash
        if (!_showOnboarding)
            Container(
              color: AppTheme.background,
              width: double.infinity,
              height: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100, height: 100,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [AppTheme.primary, Color(0xFF5BAE7A)]),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text('🤖', style: TextStyle(fontSize: 48)),
                  ),
                  const SizedBox(height: 20),
                  const Text('BAYMAX', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4, color: AppTheme.primary)),
                  const SizedBox(height: 8),
                  const Text('Your AI Fitness Companion', style: TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 32),
                  const CircularProgressIndicator(color: AppTheme.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
