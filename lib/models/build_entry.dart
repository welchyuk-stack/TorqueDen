import 'package:torqueden/models/post_media.dart';

/// A single dated update in a car's build log. Mirrors the `build_entries`
/// table in Supabase, with any attached [media] (from `post_media`).
class BuildEntry {
  const BuildEntry({
    required this.id,
    required this.carId,
    required this.title,
    this.body,
    required this.createdAt,
    this.media = const [],
  });

  final String id;
  final String carId;
  final String title;
  final String? body;
  final DateTime createdAt;
  final List<PostMedia> media;

  bool get hasMedia => media.isNotEmpty;

  factory BuildEntry.fromMap(Map<String, dynamic> map) {
    final rawMedia = (map['post_media'] as List?) ?? const [];
    final media = rawMedia
        .cast<Map<String, dynamic>>()
        .map(PostMedia.fromMap)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    return BuildEntry(
      id: map['id'] as String,
      carId: map['car_id'] as String,
      title: map['title'] as String,
      body: map['body'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      media: media,
    );
  }
}
