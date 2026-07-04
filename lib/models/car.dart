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
    );
  }

  bool get hasPhoto => photoUrl != null && photoUrl!.trim().isNotEmpty;

  /// Big title for the car card: its nickname if it has one, else make + model.
  String get title => (nickname != null && nickname!.trim().isNotEmpty)
      ? nickname!.trim()
      : '$make $model';

  /// Supporting line: "2008 BMW M3", skipping the year if unknown.
  String get subtitle =>
      [if (year != null) '$year', make, model].join(' ');
}
