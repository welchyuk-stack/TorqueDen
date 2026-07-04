/// A photo or video attached to a build update. Mirrors the `post_media` table.
class PostMedia {
  const PostMedia({
    required this.id,
    required this.url,
    this.kind = 'image',
    this.position = 0,
    this.buildEntryId,
  });

  final String id;
  final String url;

  /// 'image' or 'video'.
  final String kind;
  final int position;

  /// The build entry (post) this media belongs to — needed to wire up likes and
  /// comments. Null when the query didn't select it.
  final String? buildEntryId;

  bool get isVideo => kind == 'video';

  factory PostMedia.fromMap(Map<String, dynamic> map) {
    return PostMedia(
      id: (map['id'] as String?) ?? '',
      url: map['url'] as String,
      kind: (map['kind'] as String?) ?? 'image',
      position: (map['position'] as int?) ?? 0,
      buildEntryId: map['build_entry_id'] as String?,
    );
  }
}
