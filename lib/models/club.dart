/// A community club. Mirrors the `clubs` table in Supabase.
class Club {
  const Club({
    required this.id,
    required this.name,
    this.description,
    this.avatarUrl,
    required this.ownerId,
    required this.createdAt,
    this.isLocked = false,
    this.memberCount = 0,
  });

  final String id;
  final String name;
  final String? description;
  final String? avatarUrl;
  final String ownerId;
  final DateTime createdAt;
  final bool isLocked;

  /// Populated when the query embeds `club_members(count)`.
  final int memberCount;

  bool get hasAvatar => avatarUrl != null && avatarUrl!.trim().isNotEmpty;

  /// Reads a count out of an embedded `club_members(count)` aggregate.
  static int _embeddedCount(dynamic embedded) {
    if (embedded is List && embedded.isNotEmpty) {
      final first = embedded.first;
      if (first is Map && first['count'] is int) return first['count'] as int;
    }
    return 0;
  }

  factory Club.fromMap(Map<String, dynamic> map) {
    return Club(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      ownerId: map['owner_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      isLocked: (map['is_locked'] as bool?) ?? false,
      memberCount: _embeddedCount(map['club_members']),
    );
  }
}
