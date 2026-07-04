import 'dart:math' as math;

/// A car in someone's garage. Mirrors the `cars` table in Supabase.
class Car {
  const Car({
    required this.id,
    required this.make,
    required this.model,
    this.ownerId,
    this.year,
    this.chassisModel,
    this.nickname,
    this.color,
    this.description,
    this.photoUrl,
    this.latitude,
    this.longitude,
    this.locationName,
  });

  final String id;

  /// The id of the user who owns this car (auth.users.id). Null if not selected.
  final String? ownerId;
  final String make;
  final String model;
  final int? year;

  /// Platform / chassis code, e.g. "G87" for a BMW M2.
  final String? chassisModel;
  final String? nickname;
  final String? color;
  final String? description;

  /// Public URL of the car's photo in Supabase Storage, if it has one.
  final String? photoUrl;

  /// Where this car is based. latitude/longitude drive the Discover radius
  /// search; [locationName] is a human label like "Manchester, UK". All null
  /// when the owner didn't share a location.
  final double? latitude;
  final double? longitude;
  final String? locationName;

  factory Car.fromMap(Map<String, dynamic> map) {
    return Car(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String?,
      make: map['make'] as String,
      model: map['model'] as String,
      year: map['year'] as int?,
      chassisModel: map['chassis_model'] as String?,
      nickname: map['nickname'] as String?,
      color: map['color'] as String?,
      description: map['description'] as String?,
      photoUrl: map['photo_url'] as String?,
      // Postgres doubles can arrive as int or num over the wire.
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      locationName: map['location_name'] as String?,
    );
  }

  bool get hasPhoto => photoUrl != null && photoUrl!.trim().isNotEmpty;

  /// True when this car has usable coordinates for distance search.
  bool get hasLocation => latitude != null && longitude != null;

  /// Great-circle distance in **kilometres** from ([lat], [lng]) to this car,
  /// via the Haversine formula. Returns null if the car has no location.
  double? distanceKmFrom(double lat, double lng) {
    if (!hasLocation) return null;
    const earthRadiusKm = 6371.0;
    double toRad(double d) => d * math.pi / 180.0;
    final dLat = toRad(latitude! - lat);
    final dLng = toRad(longitude! - lng);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat)) *
            math.cos(toRad(latitude!)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Big title for the car card: its nickname if it has one, else make + model.
  String get title => (nickname != null && nickname!.trim().isNotEmpty)
      ? nickname!.trim()
      : '$make $model';

  /// Supporting line: "2008 BMW M3", skipping the year if unknown.
  String get subtitle =>
      [if (year != null) '$year', make, model].join(' ');
}
