class CarMeet {
  const CarMeet({
    required this.id,
    required this.creatorId,
    required this.title,
    required this.locationName,
    required this.meetAt,
    required this.createdAt,
    this.description,
    this.address,
    this.latitude,
    this.longitude,
    this.coverUrl,
    this.creatorUsername,
    this.creatorDisplayName,
    this.creatorAvatarUrl,
    this.goingCount = 0,
    this.maybeCount = 0,
    this.myRsvp,
  });

  final String id;
  final String creatorId;
  final String title;
  final String? description;
  final String locationName;
  final String? address;
  final double? latitude;
  final double? longitude;
  final DateTime meetAt;
  final DateTime createdAt;
  final String? coverUrl;

  // Joined from profiles
  final String? creatorUsername;
  final String? creatorDisplayName;
  final String? creatorAvatarUrl;

  // Aggregated from meet_rsvps
  final int goingCount;
  final int maybeCount;

  // Current user's RSVP status, null = not RSVPed
  final String? myRsvp;

  bool get hasCoords => latitude != null && longitude != null;
  bool get isPast => meetAt.isBefore(DateTime.now());

  String get organizerName =>
      creatorDisplayName?.trim().isNotEmpty == true
          ? creatorDisplayName!
          : creatorUsername ?? 'Unknown';

  factory CarMeet.fromMap(Map<String, dynamic> m, {String? myId}) {
    final rsvps = (m['meet_rsvps'] as List?) ?? [];
    int going = 0, maybe = 0;
    String? myRsvp;
    for (final r in rsvps) {
      final status = r['status'] as String;
      if (status == 'going') going++;
      if (status == 'maybe') maybe++;
      if (myId != null && r['user_id'] == myId) myRsvp = status;
    }
    final profile = m['creator'] as Map<String, dynamic>?;
    return CarMeet(
      id: m['id'] as String,
      creatorId: m['creator_id'] as String,
      title: m['title'] as String,
      description: m['description'] as String?,
      locationName: m['location_name'] as String,
      address: m['address'] as String?,
      latitude: (m['latitude'] as num?)?.toDouble(),
      longitude: (m['longitude'] as num?)?.toDouble(),
      meetAt: DateTime.parse(m['meet_at'] as String),
      createdAt: DateTime.parse(m['created_at'] as String),
      coverUrl: m['cover_url'] as String?,
      creatorUsername: profile?['username'] as String?,
      creatorDisplayName: profile?['display_name'] as String?,
      creatorAvatarUrl: profile?['avatar_url'] as String?,
      goingCount: going,
      maybeCount: maybe,
      myRsvp: myRsvp,
    );
  }
}
