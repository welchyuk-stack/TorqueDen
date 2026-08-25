/// A photo or video attached to a build update. Mirrors the `post_media` table.
class PostMedia {
  const PostMedia({
    required this.id,
    required this.url,
    this.kind = 'image',
    this.position = 0,
    this.buildEntryId,
    this.caption,
    this.tags = const [],
  });

  final String id;
  final String url;

  /// 'image' or 'video'.
  final String kind;
  final int position;

  /// The build entry (post) this media belongs to — needed to wire up likes and
  /// comments. Null when the query didn't select it.
  final String? buildEntryId;

  /// Caption (build_entry title) — populated when the query joins build_entries.
  final String? caption;

  /// Hashtags — populated when the query joins build_entries.
  final List<String> tags;

  bool get isVideo => kind == 'video';

  /// Returns a Supabase image-transform URL for feed thumbnails (free tier).
  /// Falls back to the original URL for videos or non-Supabase URLs.
  String thumbnailUrl({int width = 800, int quality = 75}) {
    if (isVideo) return url;
    // Swap /object/public/ → /render/image/public/ and append transform params.
    final transformed = url.replaceFirst(
      '/storage/v1/object/public/',
      '/storage/v1/render/image/public/',
    );
    if (transformed == url) return url; // not a Supabase storage URL
    return '$transformed?width=$width&quality=$quality&resize=contain';
  }

  /// Extracts the storage path (everything after the bucket name) from a
  /// Supabase public URL. Returns null if the URL isn't a storage URL.
  String? get storagePath {
    const marker = '/object/public/car-photos/';
    final idx = url.indexOf(marker);
    if (idx == -1) return null;
    return url.substring(idx + marker.length);
  }

  factory PostMedia.fromMap(Map<String, dynamic> map) {
    final entry = map['build_entry'] as Map<String, dynamic>?;
    return PostMedia(
      id: (map['id'] as String?) ?? '',
      url: map['url'] as String,
      kind: (map['kind'] as String?) ?? 'image',
      position: (map['position'] as int?) ?? 0,
      buildEntryId: map['build_entry_id'] as String?,
      caption: entry?['title'] as String?,
      tags: (entry?['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }
}
