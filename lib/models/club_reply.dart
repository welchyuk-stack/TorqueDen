/// A reply to a club thread. Mirrors the `club_replies` table.
class ClubReply {
  const ClubReply({
    required this.id,
    required this.threadId,
    required this.authorId,
    required this.body,
    required this.createdAt,
    this.authorName,
  });

  final String id;
  final String threadId;
  final String authorId;
  final String body;
  final DateTime createdAt;

  /// From embedded `author:profiles(username)`.
  final String? authorName;

  factory ClubReply.fromMap(Map<String, dynamic> map) {
    final author = map['author'];
    return ClubReply(
      id: map['id'] as String,
      threadId: map['thread_id'] as String,
      authorId: map['author_id'] as String,
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      authorName: author is Map ? author['username'] as String? : null,
    );
  }
}
