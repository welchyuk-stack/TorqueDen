/// A photo or video attached to a build update. Mirrors the `post_media` table.
class PostMedia {
  const PostMedia({
    required this.id,
    required this.url,
    this.kind = 'image',
    this.position = 0,
  });

  final String id;
  final String url;

  /// 'image' or 'video'.
  final String kind;
  final int position;

  bool get isVideo => kind == 'video';

  factory PostMedia.fromMap(Map<String, dynamic> map) {
    return PostMedia(
      id: (map['id'] as String?) ?? '',
      url: map['url'] as String,
      kind: (map['kind'] as String?) ?? 'image',
      position: (map['position'] as int?) ?? 0,
    );
  }
}
