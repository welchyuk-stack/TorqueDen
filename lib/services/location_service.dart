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

  /// Convenience: current position + its reverse-geocoded label in one call.
  static Future<LocatedPlace> currentPlace() async {
    final pos = await currentPosition();
    final label = await describe(pos.latitude, pos.longitude);
    return LocatedPlace(
      latitude: pos.latitude,
      longitude: pos.longitude,
      label: label,
    );
  }
}
