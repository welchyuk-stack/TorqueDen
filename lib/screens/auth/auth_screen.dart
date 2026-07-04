import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/wordmark.dart';

/// Combined log-in / sign-up screen. Toggling between the two modes (instead of
/// pushing separate routes) keeps things simple: when auth succeeds, the
/// AuthGate above swaps this whole screen out for the app automatically.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final auth = Supabase.instance.client.auth;
    final email = _email.text.trim();
    final password = _password.text;

    try {
      if (_isLogin) {
        await auth.signInWithPassword(email: email, password: password);
        // Success → AuthGate rebuilds into the app automatically.
      } else {
        final res = await auth.signUp(
          email: email,
          password: password,
          data: {'username': _username.text.trim()},
        );
        // If email confirmation is on, there's no session yet.
        if (res.session == null && mounted) {
          _showMessage('Account created. Check your email to confirm, then log in.');
          setState(() => _isLogin = true);
        }
      }
    } on AuthException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (_) {
      if (mounted) _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: Wordmark(fontSize: 34)),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Where the build lives.',
                        style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      _isLogin ? 'Log in' : 'Create your account',
                      style: GoogleFonts.archivo(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.cream,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (!_isLogin) ...[
                      TextFormField(
                        controller: _username,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          hintText: 'e.g. boostedmk7',
                        ),
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.length < 3) return 'At least 3 characters';
                          if (value.contains(' ')) return 'No spaces allowed';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (!value.contains('@') || !value.contains('.')) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!_loading) _submit();
                      },
                      decoration: const InputDecoration(labelText: 'Password'),
                      validator: (v) {
                        if ((v ?? '').length < 6) return 'At least 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onEmber,
                              ),
                            )
                          : Text(_isLogin ? 'Log in' : 'Create account'),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: _loading
                            ? null
                            : () => setState(() => _isLogin = !_isLogin),
                        child: Text(
                          _isLogin
                              ? 'New here? Create an account'
                              : 'Already have an account? Log in',
                          style: GoogleFonts.inter(color: AppColors.steel, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
