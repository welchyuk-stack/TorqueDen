import 'package:shared_preferences/shared_preferences.dart';

/// The user's chosen search location (set in Settings), used as the centre for
/// Discover's "near me" search. Coordinates are already fuzzed to a ~1 km grid.
/// Persisted locally.
class SavedLocation {
  SavedLocation._();

  static const _kLat = 'search_loc_lat';
  static const _kLng = 'search_loc_lng';
  static const _kLabel = 'search_loc_label';

  static double? lat;
  static double? lng;
  static String? label;

  static bool get isSet => lat != null && lng != null;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final la = p.getDouble(_kLat);
    final ln = p.getDouble(_kLng);
    if (la != null && ln != null) {
      lat = la;
      lng = ln;
      label = p.getString(_kLabel);
    }
  }

  static Future<void> save(double latitude, double longitude, String? placeLabel) async {
    lat = latitude;
    lng = longitude;
    label = placeLabel;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kLat, latitude);
    await p.setDouble(_kLng, longitude);
    if (placeLabel != null && placeLabel.isNotEmpty) {
      await p.setString(_kLabel, placeLabel);
    } else {
      await p.remove(_kLabel);
    }
  }

  static Future<void> clear() async {
    lat = null;
    lng = null;
    label = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kLat);
    await p.remove(_kLng);
    await p.remove(_kLabel);
  }
}
