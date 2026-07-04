/// A comment (or reply) on a build update. Mirrors `post_comments`, with the
/// commenter's [username] joined from `profiles`.
class PostComment {
  const PostComment({
    required this.id,
    required this.entryId,
    required this.userId,
    this.parentId,
    required this.username,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String entryId;
  final String userId;

  /// Null for a top-level comment; the parent comment's id for a reply.
  final String? parentId;
  final String username;
  final String body;
  final DateTime createdAt;

  bool get isReply => parentId != null;

  factory PostComment.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    return PostComment(
      id: map['id'] as String,
      entryId: map['build_entry_id'] as String,
      userId: map['user_id'] as String,
      parentId: map['parent_id'] as String?,
      username: (profile?['username'] as String?)?.trim().isNotEmpty == true
          ? profile!['username'] as String
          : 'someone',
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
