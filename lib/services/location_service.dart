import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Thrown when we can't get a location, with a message safe to show the user.
class LocationException implements Exception {
  const LocationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A resolved location: coordinates plus an optional human-readable label
/// like "Manchester, UK".
class LocatedPlace {
  const LocatedPlace({
    required this.latitude,
    required this.longitude,
    this.label,
  });

  final double latitude;
  final double longitude;
  final String? label;
}

/// Thin wrapper around geolocator/geocoding for the location features.
class LocationService {
  const LocationService._();

  /// Requests permission (if needed) and returns the device's current position.
  /// Throws [LocationException] with a friendly message on any failure.
  static Future<Position> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
        'Location services are turned off. Enable them in Settings to search nearby.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('Location permission was denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Location permission is permanently denied. Enable it in Settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
    );
  }

  /// Reverse-geocodes coordinates into a short label ("City, Country").
  /// Returns null if nothing sensible could be resolved — never throws.
  static Future<String?> describe(double latitude, double longitude) async {
    try {
      final marks = await Geocoding().placemarkFromCoordinates(latitude, longitude);
      if (marks.isEmpty) return null;
      final p = marks.first;
      final town = (p.locality?.isNotEmpty ?? false)
          ? p.locality
          : (p.subAdministrativeArea?.isNotEmpty ?? false)
              ? p.subAdministrativeArea
              : p.administrativeArea;
      final country = p.isoCountryCode ?? p.country;
      final parts = [
        if (town != null && town.isNotEmpty) town,
        if (country != null && country.isNotEmpty) country,
      ];
      return parts.isEmpty ? null : parts.join(', ');
    } catch (_) {
      return null;
    }
  }

  /// Coarsens a coordinate to a ~1 km grid (2 decimal places) so a car's exact
  /// home location is never stored or exposed through the API — a thief can't
  /// pinpoint it, while "near me" distances stay roughly right.
  static double fuzz(double coordinate) =>
      (coordinate * 100).roundToDouble() / 100;

  /// Convenience: current position + its reverse-geocoded label in one call.
  /// The label is resolved from the exact point (accurate town name), but the
  /// returned coordinates are fuzzed for storage.
  static Future<LocatedPlace> currentPlace() async {
    final pos = await currentPosition();
    final label = await describe(pos.latitude, pos.longitude);
    return LocatedPlace(
      latitude: fuzz(pos.latitude),
      longitude: fuzz(pos.longitude),
      label: label,
    );
  }

  /// Forward-geocodes a typed place (town, postcode, "City, Country") into a
  /// [LocatedPlace]. Coordinates are fuzzed to the ~1 km grid, and the label is
  /// resolved back from those coordinates for a consistent "Town, Country".
  /// Throws [LocationException] if nothing matches.
  static Future<LocatedPlace> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) throw const LocationException('Enter a place to search for.');
    List<Location> results;
    try {
      results = await Geocoding().locationFromAddress(trimmed);
    } catch (_) {
      throw const LocationException('Couldn\'t look that place up. Check your connection and try again.');
    }
    if (results.isEmpty) throw const LocationException('No place found for that search.');
    final loc = results.first;
    final label = await describe(loc.latitude, loc.longitude);
    return LocatedPlace(
      latitude: fuzz(loc.latitude),
      longitude: fuzz(loc.longitude),
      label: label ?? trimmed,
    );
  }
}
