/// A reply to a club thread. Mirrors the `club_replies` table, with a
/// thumbs-up/down [score] and the current user's [myVote] (-1, 0 or 1).
class ClubReply {
  const ClubReply({
    required this.id,
    required this.threadId,
    required this.authorId,
    required this.body,
    required this.createdAt,
    this.parentId,
    this.authorName,
    this.score = 0,
    this.myVote = 0,
  });

  final String id;
  final String threadId;
  final String authorId;
  final String body;
  final DateTime createdAt;

  /// Null for a top-level reply; otherwise the reply this one answers.
  final String? parentId;

  /// From embedded `author:profiles(username)`.
  final String? authorName;

  /// Net score (sum of votes) and the signed-in user's own vote.
  final int score;
  final int myVote;

  ClubReply copyWith({int? score, int? myVote}) => ClubReply(
        id: id,
        threadId: threadId,
        authorId: authorId,
        body: body,
        createdAt: createdAt,
        parentId: parentId,
        authorName: authorName,
        score: score ?? this.score,
        myVote: myVote ?? this.myVote,
      );

  factory ClubReply.fromMap(Map<String, dynamic> map, {String? currentUserId}) {
    final author = map['author'];
    final votes = (map['club_reply_votes'] as List?) ?? const [];
    var score = 0;
    var myVote = 0;
    for (final v in votes.cast<Map<String, dynamic>>()) {
      final value = (v['value'] as num?)?.toInt() ?? 0;
      score += value;
      if (currentUserId != null && v['user_id'] == currentUserId) myVote = value;
    }
    return ClubReply(
      id: map['id'] as String,
      threadId: map['thread_id'] as String,
      authorId: map['author_id'] as String,
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      parentId: map['parent_id'] as String?,
      authorName: author is Map ? author['username'] as String? : null,
      score: score,
      myVote: myVote,
    );
  }
}
