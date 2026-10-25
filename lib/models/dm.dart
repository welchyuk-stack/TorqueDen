/// A 1-to-1 DM thread row, with the other participant's profile joined in.
class DmThread {
  const DmThread({
    required this.id,
    required this.otherUserId,
    required this.otherUsername,
    required this.lastMessageAt,
    this.otherDisplayName,
    this.otherAvatarUrl,
    this.lastBody,
    this.unreadCount = 0,
  });

  final String id;
  final String otherUserId;
  final String otherUsername;
  final String? otherDisplayName;
  final String? otherAvatarUrl;
  final DateTime lastMessageAt;
  final String? lastBody;
  final int unreadCount;

  String get displayName =>
      (otherDisplayName?.trim().isNotEmpty ?? false) ? otherDisplayName! : '@$otherUsername';

  factory DmThread.fromMap(Map<String, dynamic> m, String myId) {
    final isA = (m['participant_a'] as String) == myId;
    final other = isA
        ? m['profile_b'] as Map<String, dynamic>
        : m['profile_a'] as Map<String, dynamic>;
    return DmThread(
      id: m['id'] as String,
      otherUserId: other['id'] as String,
      otherUsername: other['username'] as String,
      otherDisplayName: other['display_name'] as String?,
      otherAvatarUrl: other['avatar_url'] as String?,
      lastMessageAt: DateTime.parse(m['last_message_at'] as String),
      lastBody: m['last_body'] as String?,
      unreadCount: (m['unread_count'] as int?) ?? 0,
    );
  }
}

/// One message in a DM thread.
class DmMessage {
  const DmMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String threadId;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  factory DmMessage.fromMap(Map<String, dynamic> m) => DmMessage(
        id: m['id'] as String,
        threadId: m['thread_id'] as String,
        senderId: m['sender_id'] as String,
        body: m['body'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        readAt: m['read_at'] == null ? null : DateTime.parse(m['read_at'] as String),
      );
}
