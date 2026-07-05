import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/iap/iap_service.dart';
import 'package:torqueden/push/push_service.dart';
import 'package:torqueden/main_shell.dart';
import 'package:torqueden/screens/auth/auth_screen.dart';
import 'package:torqueden/screens/auth/set_new_password_screen.dart';

/// Decides what the user sees based on login state:
///   password recovery → set-new-password screen
///   logged in         → the 4-tab app (MainShell)
///   logged out        → the auth screen (log in / sign up)
///
/// Listens to Supabase's auth state stream, so it swaps automatically the
/// instant someone logs in, signs up, logs out, or opens a reset link.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = Supabase.instance.client.auth;
  late final StreamSubscription<AuthState> _sub;
  bool _recovering = false;

  @override
  void initState() {
    super.initState();
    _sub = _auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) _recovering = true;
      // Keep RevenueCat's app-user in step with the Supabase session so the
      // purchase webhook maps to the right user_entitlements row.
      final uid = state.session?.user.id;
      if (state.event == AuthChangeEvent.signedIn && uid != null) {
        IapService.instance.identify(uid);
        PushService.instance.registerForUser();
      } else if (state.event == AuthChangeEvent.signedOut) {
        IapService.instance.signOut();
        PushService.instance.unregister();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_recovering) {
      return SetNewPasswordScreen(onDone: () => setState(() => _recovering = false));
    }
    if (_auth.currentSession != null) return const MainShell();
    return const AuthScreen();
  }
}
