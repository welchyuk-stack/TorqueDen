import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App theme preference: Dark, Light, or follow the OS setting.
/// Persisted locally; defaults to Dark (the app's original, shipping look).
class ThemePref {
  ThemePref._();

  static const String _key = 'theme_mode';

  /// Live value the app listens to — changing it rebuilds the whole tree
  /// (see `TorqueDenApp` in main.dart) so every `AppColors.*` reference
  /// re-evaluates against the new brightness.
  static final ValueNotifier<ThemeMode> notifier = ValueNotifier(ThemeMode.dark);

  static ThemeMode get mode => notifier.value;

  /// Load the saved preference. Call once at startup.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    notifier.value = _decode(prefs.getString(_key));
  }

  static Future<void> setMode(ThemeMode mode) async {
    notifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  static ThemeMode _decode(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
}
