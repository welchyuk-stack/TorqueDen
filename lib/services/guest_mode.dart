import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks whether the user chose to browse without an account.
/// Cleared automatically when they sign in.
class GuestMode {
  GuestMode._();

  static final ValueNotifier<bool> _active = ValueNotifier(false);

  static bool get active => _active.value;
  static ValueNotifier<bool> get notifier => _active;

  static void enable() => _active.value = true;

  /// Call on sign-in and sign-out so the AuthGate routes correctly.
  static void clear() => _active.value = false;

  /// Returns true when there is no Supabase session (covers both guest mode
  /// and the unauthenticated state before sign-in).
  static bool get isGuest =>
      Supabase.instance.client.auth.currentSession == null;
}
