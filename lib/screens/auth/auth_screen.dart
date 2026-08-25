import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/services/guest_mode.dart';
import 'package:torqueden/services/turnstile.dart';
import 'package:torqueden/support_links.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/utils/open_link.dart';
import 'package:torqueden/widgets/wordmark.dart';

/// Deep-link the password-reset email points back to. Must be added to
/// Supabase → Authentication → URL Configuration → Redirect URLs, and matches
/// the URL scheme registered in iOS Info.plist / Android manifest.
const String kResetRedirect = 'io.torqueden://reset-callback';

/// Combined log-in / sign-up screen. Toggling between the two modes (instead of
/// pushing separate routes) keeps things simple: when auth succeeds, the
/// AuthGate above swaps this whole screen out for the app automatically.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.initialLogin = true});

  /// When false, the screen opens in sign-up mode (e.g. from "Create account").
  final bool initialLogin;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  late bool _isLogin;
  bool _loading = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _isLogin = widget.initialLogin;
  }

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

    // No-op while Turnstile is unconfigured; returns null and the calls below
    // behave exactly as before. Once enabled, a dismissed sheet aborts rather
    // than falling through — GoTrue would reject a tokenless request anyway.
    String? captcha;
    if (TurnstileConfig.enabled) {
      captcha = await obtainTurnstileToken(context);
      if (!mounted) return;
      if (captcha == null) {
        setState(() => _loading = false);
        _showMessage('Could not verify you\'re human. Please try again.');
        return;
      }
    }

    try {
      if (_isLogin) {
        await auth.signInWithPassword(
          email: email,
          password: password,
          captchaToken: captcha,
        );
        if (mounted) {
          GuestMode.clear();
          Navigator.of(context).popUntil((r) => r.isFirst);
        }
      } else {
        final res = await auth.signUp(
          email: email,
          password: password,
          data: {'username': _username.text.trim()},
          captchaToken: captcha,
        );
        if (res.session != null && mounted) {
          // Signed up and auto-confirmed — go straight in.
          GuestMode.clear();
          Navigator.of(context).popUntil((r) => r.isFirst);
        } else if (mounted) {
          // Email confirmation required.
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

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      _showMessage('Enter your email above, then tap "Forgot password".');
      return;
    }
    setState(() => _loading = true);

    // Reset is the cheapest endpoint to abuse for mailbombing, so it takes the
    // same check as signup and login.
    String? captcha;
    if (TurnstileConfig.enabled) {
      captcha = await obtainTurnstileToken(context);
      if (!mounted) return;
      if (captcha == null) {
        setState(() => _loading = false);
        _showMessage('Could not verify you\'re human. Please try again.');
        return;
      }
    }

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: kResetRedirect,
        captchaToken: captcha,
      );
      if (mounted) _showMessage('Password reset link sent to $email. Check your inbox.');
    } on AuthException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (_) {
      if (mounted) _showMessage('Could not send the reset email. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      appBar: canPop
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                color: AppColors.steel,
                onPressed: () => Navigator.of(context).pop(),
              ),
            )
          : null,
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
                      style: GoogleFonts.spaceGrotesk(
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
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!_loading) _submit();
                      },
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: AppColors.steel,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        final value = v ?? '';
                        // Only new passwords get the stronger minimum — applying
                        // it at login would lock out existing shorter passwords.
                        if (_isLogin) {
                          return value.isEmpty ? 'Enter your password' : null;
                        }
                        if (value.length < 8) return 'At least 8 characters';
                        return null;
                      },
                    ),
                    if (_isLogin)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _loading ? null : _forgotPassword,
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                          child: Text('Forgot password?',
                              style: GoogleFonts.inter(color: AppColors.steel, fontSize: 13)),
                        ),
                      ),
                    SizedBox(height: _isLogin ? 8 : 24),
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
                    if (!_isLogin) ...[
                      const SizedBox(height: 14),
                      _ConsentLine(
                        onTerms: () => openLink(context, SupportLinks.termsUrl),
                        onPrivacy: () => openLink(context, SupportLinks.privacyPolicyUrl),
                        onGuidelines: () => openLink(context, SupportLinks.communityGuidelinesUrl),
                      ),
                    ],
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
                    const SizedBox(height: 4),
                    Center(
                      child: Column(
                        children: [
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () {
                                    GuestMode.enable();
                                    if (Navigator.of(context).canPop()) {
                                      Navigator.of(context).pop();
                                    }
                                  },
                            child: Text(
                              'Browse as guest',
                              style: GoogleFonts.inter(
                                color: AppColors.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            'Read-only — some features require an account',
                            style: GoogleFonts.inter(
                              color: AppColors.textMuted.withValues(alpha: 0.6),
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
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

/// "By creating an account you agree to our Terms and Privacy Policy" with the
/// two documents tappable.
class _ConsentLine extends StatelessWidget {
  const _ConsentLine({required this.onTerms, required this.onPrivacy, required this.onGuidelines});
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;
  final VoidCallback onGuidelines;

  @override
  Widget build(BuildContext context) {
    final muted = GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12, height: 1.4);
    final link = GoogleFonts.inter(color: AppColors.ember, fontSize: 12, fontWeight: FontWeight.w600, height: 1.4);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('By creating an account you agree to our ', style: muted),
        InkWell(onTap: onTerms, child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Terms', style: link))),
        Text(', ', style: muted),
        InkWell(onTap: onPrivacy, child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Privacy Policy', style: link))),
        Text(' and ', style: muted),
        InkWell(onTap: onGuidelines, child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Community Guidelines', style: link))),
        Text('.', style: muted),
      ],
    );
  }
}
