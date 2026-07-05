import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Remote push via Firebase Cloud Messaging. Registers this device's FCM token
/// against the logged-in user in `device_tokens`; a Supabase Edge Function
/// (send-push) delivers a push to those tokens whenever a notification row is
/// created.
///
/// Everything is guarded: [init] is a no-op until a Firebase project is wired
/// (GoogleService-Info.plist present), so the app runs fine before push exists.
/// See NOTIFICATIONS-SETUP.md.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _ready = false;
  FirebaseMessaging? _messaging;

  /// Whether Firebase initialised (a project is configured).
  bool get isAvailable => _ready;

  /// Initialise Firebase + messaging once. Safe to call at startup; fails
  /// quietly (leaving push off) if Firebase isn't configured yet.
  Future<void> init() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      _messaging = FirebaseMessaging.instance;
      _messaging!.onTokenRefresh.listen(_saveToken);
      _ready = true;
    } catch (_) {
      _ready = false; // Firebase not configured — carry on without push.
    }
  }

  /// Ask for notification permission and register this device's token. Call on
  /// login (after [init]).
  Future<void> registerForUser() async {
    final messaging = _messaging;
    if (!_ready || messaging == null) return;
    try {
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) await _saveToken(token);
    } catch (_) {}
  }

  Future<void> _saveToken(String token) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client.from('device_tokens').upsert({
        'token': token,
        'user_id': uid,
        'platform': Platform.isIOS
            ? 'ios'
            : Platform.isAndroid
                ? 'android'
                : 'other',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'token');
    } catch (_) {}
  }

  /// On logout: drop this device's token so it stops receiving the user's push.
  Future<void> unregister() async {
    final messaging = _messaging;
    if (!_ready || messaging == null) return;
    try {
      final token = await messaging.getToken();
      if (token != null) {
        await Supabase.instance.client
            .from('device_tokens')
            .delete()
            .eq('token', token);
      }
      await messaging.deleteToken();
    } catch (_) {}
  }
}
