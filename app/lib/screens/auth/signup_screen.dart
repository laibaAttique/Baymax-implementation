import 'package:flutter/material.dart';
import '../../services/auth_flow.dart';
import '../../services/auth_service.dart';
import '../../utils/validators.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand.dart';
import '../../widgets/glass.dart';
import 'login_screen.dart';
import '../health_profiling/step1_personal_info.dart';
import '../../models/health_profile.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  _SignupScreenState createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _confirmPassCtrl = TextEditingController();
  
  bool _obscureText = true;
  bool _isLoading = false;
  bool _agreedToTerms = false;

  /// 0–4: one point each for 8+ characters, an uppercase letter, a digit and a symbol.
  int get _strength {
    final p = _passCtrl.text;
    return [
      p.length >= 8,
      RegExp(r'[A-Z]').hasMatch(p),
      RegExp(r'[0-9]').hasMatch(p),
      RegExp(r'[^A-Za-z0-9]').hasMatch(p),
    ].where((ok) => ok).length;
  }

  String get _strengthLabel => const ['Very weak', 'Weak', 'Fair', 'Good', 'Strong'][_strength];

  Color get _strengthColor => _strength <= 1 ? AppTheme.error : (_strength == 2 ? AppTheme.warning : AppTheme.success);

  // Each field shows its message next to it once the user has typed in it (mockup M2 and NFR-U2).
  final Set<String> _touched = {};
  void _touch(String f) => setState(() => _touched.add(f));

  String? get _nameError => _touched.contains('name') ? Validators.fullName(_nameCtrl.text) : null;
  String? get _emailError => _touched.contains('email') ? Validators.email(_emailCtrl.text) : null;
  String? get _passError => _touched.contains('pass') ? Validators.password(_passCtrl.text) : null;
  String? get _confirmError => _touched.contains('confirm') ? Validators.confirmPassword(_passCtrl.text, _confirmPassCtrl.text) : null;

  /// The Create Account button stays disabled until every field is valid and the terms box is ticked.
  bool get _formValid =>
      Validators.fullName(_nameCtrl.text) == null &&
      Validators.email(_emailCtrl.text) == null &&
      Validators.password(_passCtrl.text) == null &&
      Validators.confirmPassword(_passCtrl.text, _confirmPassCtrl.text) == null &&
      _agreedToTerms;

  Future<void> _signup() async {
    if (!_formValid) return;
    setState(() => _isLoading = true);
    try {
      await AuthService.instance.signUp(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        displayName: _nameCtrl.text.trim(),
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => Step1PersonalInfo(profile: HealthProfile(fullName: _nameCtrl.text.trim()))),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Module 1 FR2.6: sign up with Google. The account takes the verified Google email and name; the profiling steps follow.
  Future<void> _signupWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await AuthService.instance.signInWithGoogle();
      if (mounted) await AuthFlow.continueAfterAuth(context);
    } on AuthException catch (e) {
      if (mounted && !e.cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Reveal(child: BrandMark(size: 60)),
                  const SizedBox(height: 22),
                  const Reveal(index: 1, child: Text('Create account', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -1))),
                  const SizedBox(height: 6),
                  const Reveal(index: 2, child: Text('Join Baymax and start your health journey.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 15, fontWeight: FontWeight.w500))),
                  const SizedBox(height: 26),
                  Reveal(
                    index: 3,
                    child: GlassCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _nameCtrl,
                            textInputAction: TextInputAction.next,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.name],
                            onChanged: (_) => _touch('name'),
                            decoration: InputDecoration(labelText: 'Full name', prefixIcon: const Icon(Icons.person_outline_rounded), errorText: _nameError),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            onChanged: (_) => _touch('email'),
                            decoration: InputDecoration(labelText: 'Email', prefixIcon: const Icon(Icons.mail_outline_rounded), errorText: _emailError),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passCtrl,
                            obscureText: _obscureText,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newPassword],
                            onChanged: (_) => _touch('pass'),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              errorText: _passError,
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                tooltip: _obscureText ? 'Show password' : 'Hide password',
                                icon: Icon(_obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: AppTheme.textSecondary),
                                onPressed: () => setState(() => _obscureText = !_obscureText),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 6),
                            child: Row(
                              children: [
                                for (var i = 0; i < 4; i++) ...[
                                  if (i > 0) const SizedBox(width: 4),
                                  Expanded(
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 250),
                                      height: 5,
                                      decoration: BoxDecoration(color: i < _strength ? _strengthColor : const Color(0xFFDDE0F5), borderRadius: BorderRadius.circular(3)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Text(
                            _passCtrl.text.isEmpty ? 'Use 8+ chars with uppercase, number & symbol' : 'Password strength: $_strengthLabel',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _passCtrl.text.isEmpty ? AppTheme.textSecondary : _strengthColor),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _confirmPassCtrl,
                            obscureText: _obscureText,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.newPassword],
                            onChanged: (_) => _touch('confirm'),
                            decoration: InputDecoration(labelText: 'Confirm password', prefixIcon: const Icon(Icons.lock_outline_rounded), errorText: _confirmError),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(value: _agreedToTerms, onChanged: (val) => setState(() => _agreedToTerms = val ?? false), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text('I agree to the ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5)),
                              _link('Terms of Service', () => showLegalSheet(context, privacy: false)),
                              const Text(' & ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5)),
                              _link('Privacy Policy', () => showLegalSheet(context, privacy: true)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  GlowButton(label: 'Create account', loading: _isLoading, onPressed: (_isLoading || !_formValid) ? null : _signup),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('or', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600))),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _signupWithGoogle,
                    icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
                    label: const Text('Sign up with Google'),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Already have an account?', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                      TextButton(
                        onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                        child: const Text('Log in'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _link(String text, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 1),
          child: Text(text, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 13.5, decoration: TextDecoration.underline, decorationColor: AppTheme.primary)),
        ),
      );
}
