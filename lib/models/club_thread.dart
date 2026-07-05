/// A discussion thread (question/post) inside a club. Mirrors `club_threads`.
class ClubThread {
  const ClubThread({
    required this.id,
    required this.clubId,
    required this.authorId,
    required this.title,
    this.body,
    required this.createdAt,
    this.authorName,
    this.replyCount = 0,
  });

  final String id;
  final String clubId;
  final String authorId;
  final String title;
  final String? body;
  final DateTime createdAt;

  /// From embedded `author:profiles(username)`.
  final String? authorName;

  /// From embedded `club_replies(count)`.
  final int replyCount;

  static int _embeddedCount(dynamic embedded) {
    if (embedded is List && embedded.isNotEmpty) {
      final first = embedded.first;
      if (first is Map && first['count'] is int) return first['count'] as int;
    }
    return 0;
  }

  static String? _authorName(dynamic embedded) {
    if (embedded is Map) return embedded['username'] as String?;
    return null;
  }

  factory ClubThread.fromMap(Map<String, dynamic> map) {
    return ClubThread(
      id: map['id'] as String,
      clubId: map['club_id'] as String,
      authorId: map['author_id'] as String,
      title: map['title'] as String,
      body: map['body'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      authorName: _authorName(map['author']),
      replyCount: _embeddedCount(map['club_replies']),
    );
  }
}
