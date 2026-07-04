import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/main_shell.dart';
import 'package:torqueden/screens/auth/auth_screen.dart';

/// Decides what the user sees based on login state:
///   logged in  → the 4-tab app (MainShell)
///   logged out → the auth screen (log in / sign up)
///
/// It listens to Supabase's auth state stream, so it swaps automatically the
/// instant someone logs in, signs up, or logs out — no manual navigation.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = auth.currentSession;
        if (session != null) {
          return const MainShell();
        }
        return const AuthScreen();
      },
    );
  }
}
