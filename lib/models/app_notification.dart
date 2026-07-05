/// One in-app notification row, with the actor's profile joined in for display.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.read,
    required this.createdAt,
    this.body,
    this.actorLabel,
    this.actorAvatarUrl,
    this.buildEntryId,
    this.carId,
    this.clubId,
    this.threadId,
  });

  final String id;
  final String type; // new_follower | post_comment | post_like | club_new_thread | thread_reply | comment_reply
  final String title;
  final String? body;
  final bool read;
  final DateTime createdAt;

  final String? actorLabel;
  final String? actorAvatarUrl;

  // Context for (future) deep-linking.
  final String? buildEntryId;
  final String? carId;
  final String? clubId;
  final String? threadId;

  factory AppNotification.fromMap(Map<String, dynamic> m) {
    final actor = m['actor'] as Map<String, dynamic>?;
    String? label;
    if (actor != null) {
      final display = (actor['display_name'] as String?)?.trim();
      final username = actor['username'] as String?;
      label = (display != null && display.isNotEmpty)
          ? display
          : (username != null ? '@$username' : null);
    }
    return AppNotification(
      id: m['id'] as String,
      type: m['type'] as String,
      title: m['title'] as String,
      body: m['body'] as String?,
      read: (m['read'] as bool?) ?? false,
      createdAt: DateTime.parse(m['created_at'] as String),
      actorLabel: label,
      actorAvatarUrl: actor?['avatar_url'] as String?,
      buildEntryId: m['build_entry_id'] as String?,
      carId: m['car_id'] as String?,
      clubId: m['club_id'] as String?,
      threadId: m['thread_id'] as String?,
    );
  }
}
