import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional biometric app-lock. When enabled, the app requires Face ID / Touch
/// ID (or the device passcode) to unlock a logged-in session. The preference is
/// stored locally; the Supabase session itself stays persisted as normal.
class BiometricLock {
  BiometricLock._();

  static const _key = 'biometric_lock_enabled';
  static final _auth = LocalAuthentication();

  static bool _enabled = false;

  /// Whether the user has turned biometric unlock on.
  static bool get enabled => _enabled;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _enabled = p.getBool(_key) ?? false;
  }

  /// Is any biometric / device credential actually available on this device?
  static Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Prompt for biometrics. Returns true on success. [reason] is shown to the user.
  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  /// Turn the lock on (requires a successful prompt first) or off.
  static Future<bool> setEnabled(bool value) async {
    if (value) {
      final ok = await authenticate('Confirm it\'s you to turn on biometric unlock');
      if (!ok) return false;
    }
    _enabled = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, value);
    return true;
  }
}
