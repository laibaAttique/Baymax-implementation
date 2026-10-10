import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
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

  Future<void> _signup() async {
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please agree to the Terms of Service')));
      return;
    }
    if (_passCtrl.text != _confirmPassCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }
    if (_passCtrl.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password must be at least 8 characters')));
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Baymax')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('Create Account', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            const Text('Join Baymax and start your health journey', style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 32),
            
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _passCtrl,
              obscureText: _obscureText,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility, color: AppTheme.textSecondary),
                  onPressed: () => setState(() => _obscureText = !_obscureText),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: i < _strength ? _strengthColor : AppTheme.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _passCtrl.text.isEmpty
                    ? 'Use 8+ chars with uppercase, number & symbol'
                    : 'Password strength: $_strengthLabel',
                style: TextStyle(fontSize: 12, color: _passCtrl.text.isEmpty ? AppTheme.textSecondary : _strengthColor),
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _confirmPassCtrl,
              obscureText: _obscureText,
              decoration: const InputDecoration(labelText: 'Confirm Password'),
            ),
            const SizedBox(height: 24),
            
            Row(
              children: [
                Checkbox(
                  value: _agreedToTerms,
                  activeColor: AppTheme.primary,
                  onChanged: (val) => setState(() => _agreedToTerms = val ?? false),
                ),
                Expanded(
                  child: RichText(
                    text: const TextSpan(
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      children: [
                        TextSpan(text: 'I agree to the '),
                        TextSpan(text: 'Terms of Service', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                        TextSpan(text: ' & '),
                        TextSpan(text: 'Privacy Policy', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            ElevatedButton(
              onPressed: _isLoading ? null : _signup,
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Create Account'),
            ),
            
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Already have an account? ", style: TextStyle(color: AppTheme.textSecondary)),
                GestureDetector(
                  onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                  child: const Text('Log In', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
