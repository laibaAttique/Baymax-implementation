import 'package:flutter/material.dart';
import '../../services/auth_flow.dart';
import '../../services/auth_service.dart';
import '../../services/login_guard.dart';
import '../../utils/validators.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand.dart';
import '../../widgets/glass.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  bool _obscureText = true;
  bool _isLoading = false;

  bool _emailTouched = false;
  bool _passTouched = false;

  String? get _emailError => _emailTouched ? Validators.email(_emailCtrl.text) : null;
  String? get _passError => _passTouched && _passCtrl.text.isEmpty ? 'Enter your password.' : null;

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    setState(() {
      _emailTouched = true;
      _passTouched = true;
    });
    if (Validators.email(email) != null || _passCtrl.text.isEmpty) return;

    // Module 1 (mockup M3): five failed logins in a row lock the account for 15 minutes.
    final locked = LoginGuard.instance.lockedFor(email);
    if (locked != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Too many failed attempts. Try again in ${LoginGuard.describe(locked)}.')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await AuthService.instance.signIn(email: email, password: _passCtrl.text);
      LoginGuard.instance.recordSuccess(email);
      if (mounted) await AuthFlow.continueAfterAuth(context);
    } on AuthException catch (e) {
      if (mounted) {
        var message = e.message;
        if (e.badCredentials) {
          final left = LoginGuard.instance.recordFailure(email);
          message = left == 0
              ? 'Too many failed attempts. This account is locked for ${LoginGuard.describe(LoginGuard.lockDuration)}.'
              : '${e.message} $left ${left == 1 ? 'attempt' : 'attempts'} left.';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
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

  Future<void> _forgotPassword() async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset password'),
        content: TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, emailCtrl.text.trim()), child: const Text('Send link')),
        ],
      ),
    );
    if (email == null || email.isEmpty || !mounted) return;

    try {
      await AuthService.instance.sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('If an account exists for that email, a reset link has been sent.')),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
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
                  const Reveal(index: 1, child: Text('Welcome back', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -1))),
                  const SizedBox(height: 6),
                  const Reveal(index: 2, child: Text('Log in to continue your health and fitness journey.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 15, height: 1.4, fontWeight: FontWeight.w500))),
                  const SizedBox(height: 28),
                  Reveal(
                    index: 3,
                    child: GlassCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          TextField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            onChanged: (_) => setState(() => _emailTouched = true),
                            decoration: InputDecoration(labelText: 'Email', prefixIcon: const Icon(Icons.mail_outline_rounded), errorText: _emailError),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passCtrl,
                            obscureText: _obscureText,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onSubmitted: (_) => _isLoading ? null : _login(),
                            onChanged: (_) => setState(() => _passTouched = true),
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
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(onPressed: _isLoading ? null : _forgotPassword, child: const Text('Forgot password?')),
                          ),
                          GlowButton(label: 'Log in', loading: _isLoading, onPressed: _isLoading ? null : _login),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('or', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600))),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 22),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _loginWithGoogle,
                    icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
                    label: const Text('Continue with Google'),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account?", style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                      TextButton(
                        onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SignupScreen())),
                        child: const Text('Sign up'),
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
}
