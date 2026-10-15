import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../services/auth_flow.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand.dart';
import '../../widgets/glass.dart';
import '../test.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _showOnboarding = false;
  Timer? _auto;

  static const _slides = <({IconData icon, String title, String desc})>[
    (
      icon: Icons.favorite_rounded,
      title: 'Know your health risk',
      desc: 'A screening based on your BMI, medical history and fitness data. Decision support, not a diagnosis.'
    ),
    (
      icon: Icons.fitness_center_rounded,
      title: 'Workouts built for you',
      desc: 'Weekly plans that respect your health conditions, with step-by-step technique and a built-in timer.'
    ),
    (
      icon: Icons.restaurant_menu_rounded,
      title: 'Smart nutrition',
      desc: 'Calorie tracking, allergen checks on product labels and meal plans that avoid what you cannot eat.'
    ),
  ];

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), () async {
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
    _auto?.cancel();
    _auto = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_showOnboarding || !_pageController.hasClients) return;
      final next = (_currentPage + 1) % _slides.length;
      _pageController.animateToPage(next, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Widget _splash() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.elasticOut,
            builder: (context, v, child) => Transform.scale(scale: v, child: child),
            child: const BrandMark(size: 104),
          ),
          const SizedBox(height: 24),
          const Reveal(child: Text('BAYMAX', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 6, color: AppTheme.textPrimary))),
          const SizedBox(height: 6),
          const Reveal(index: 2, child: Text('Your health and fitness companion', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600))),
          const SizedBox(height: 36),
          const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6)),
        ],
      ),
    );
  }

  Widget _onboarding() {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 28),
                  GestureDetector(
                    // Development builds only: long-press the logo to confirm which copy of the project is running.
                    onLongPress: kDebugMode ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TestScreen())) : null,
                    child: const Reveal(child: BrandMark(size: 76)),
                  ),
                  const SizedBox(height: 22),
                  const Reveal(
                    index: 1,
                    child: Text('Your health & fitness\ncompanion',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 31, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.9, color: AppTheme.textPrimary)),
                  ),
                  const SizedBox(height: 8),
                  const Reveal(index: 2, child: Text('Personalized. Smart. Safe.', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontSize: 14.5))),
                  const SizedBox(height: 30),
                  SizedBox(
                    height: 262,
                    child: PageView.builder(
                      controller: _pageController,
                      clipBehavior: Clip.none,
                      onPageChanged: (idx) => setState(() => _currentPage = idx),
                      itemCount: _slides.length,
                      itemBuilder: (context, index) {
                        final slide = _slides[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GlassCard(
                            radius: AppTheme.rHero,
                            padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconWell(icon: slide.icon, size: 68, filled: true),
                                const SizedBox(height: 18),
                                Text(slide.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.4)),
                                const SizedBox(height: 8),
                                Text(slide.desc, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (index) {
                      return Semantics(
                        button: true,
                        label: 'Go to page ${index + 1}',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _pageController.animateToPage(index, duration: const Duration(milliseconds: 360), curve: Curves.easeOutCubic),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              width: _currentPage == index ? 26 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _currentPage == index ? AppTheme.primary : const Color(0xFFC3C8E6),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 22),
                  GlowButton(
                    icon: Icons.arrow_forward_rounded,
                    label: 'Get started',
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupScreen())),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Already have an account?', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                      TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                        child: const Text('Log in'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        switchInCurve: Curves.easeOutCubic,
        child: KeyedSubtree(key: ValueKey(_showOnboarding), child: _showOnboarding ? _onboarding() : _splash()),
      ),
    );
  }
}
