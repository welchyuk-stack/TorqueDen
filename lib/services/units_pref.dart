import 'package:shared_preferences/shared_preferences.dart';

/// Distance-units preference. **Kilometres by default**; the user can switch to
/// miles in Settings. Persisted locally (device-level display preference).
class UnitsPref {
  UnitsPref._();

  static const String _key = 'distance_in_miles';
  static const double milesPerKm = 0.621371;

  static bool _useMiles = false;

  /// True if distances should display in miles. Defaults to false (km).
  static bool get useMiles => _useMiles;

  /// Load the saved preference. Call once at startup.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _useMiles = prefs.getBool(_key) ?? false;
  }

  static Future<void> setUseMiles(bool value) async {
    _useMiles = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  /// Short unit label for the current preference.
  static String get unit => _useMiles ? 'mi' : 'km';

  /// Convert a kilometre value into the display unit's number.
  static double fromKm(double km) => _useMiles ? km * milesPerKm : km;

  /// A rounded radius label, e.g. "50 km" / "31 mi", from a radius in km.
  static String radiusLabel(double km) => '${fromKm(km).round()} $unit';

  /// A "distance away" label from a distance in km:
  /// "12 km away" / "0.4 mi away" / "Here".
  static String distanceLabel(double km) {
    final v = fromKm(km);
    if (v < 0.1) return 'Here';
    if (v < 10) return '${v.toStringAsFixed(1)} $unit away';
    return '${v.round()} $unit away';
  }
}
