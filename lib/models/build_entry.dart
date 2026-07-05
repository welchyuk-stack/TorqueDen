import 'package:torqueden/models/post_media.dart';

/// A single dated update in a car's build log. Mirrors the `build_entries`
/// table in Supabase, with any attached [media] (from `post_media`).
class BuildEntry {
  const BuildEntry({
    required this.id,
    required this.carId,
    required this.title,
    this.body,
    this.category,
    required this.createdAt,
    this.media = const [],
    this.linkedModLabel,
    this.linkedCategory,
  });

  final String id;
  final String carId;
  final String title;
  final String? body;

  /// Optional mod category, e.g. "Exhaust" or "Suspension". Null for a plain
  /// build update that isn't a specific mod.
  final String? category;
  final DateTime createdAt;
  final List<PostMedia> media;

  /// A short label for the mod this post links to (e.g. "Exhaust · Cat-back"),
  /// or null if it isn't linked to one.
  final String? linkedModLabel;

  /// The category of the mod this entry links to (e.g. "Suspension"), if any.
  /// Used to file linked posts under the right section in the build log.
  final String? linkedCategory;

  bool get hasMedia => media.isNotEmpty;
  bool get hasCategory => category != null && category!.trim().isNotEmpty;
  bool get hasLinkedMod => linkedModLabel != null && linkedModLabel!.isNotEmpty;

  /// Which build-log section this entry belongs to: its own category, else the
  /// linked mod's category, else null (→ "General").
  String? get effectiveCategory {
    if (hasCategory) return category!.trim();
    final lc = linkedCategory?.trim();
    return (lc != null && lc.isNotEmpty) ? lc : null;
  }

  /// Builds a "Category · Title" label from an embedded linked build entry.
  static String? _labelFromLinked(Map<String, dynamic>? linked) {
    if (linked == null) return null;
    final title = linked['title'] as String?;
    if (title == null || title.isEmpty) return null;
    final category = linked['category'] as String?;
    return (category != null && category.isNotEmpty) ? '$category · $title' : title;
  }

  factory BuildEntry.fromMap(Map<String, dynamic> map) {
    final rawMedia = (map['post_media'] as List?) ?? const [];
    final media = rawMedia
        .cast<Map<String, dynamic>>()
        .map(PostMedia.fromMap)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    final linked = map['linked'] as Map<String, dynamic>?;
    return BuildEntry(
      id: map['id'] as String,
      carId: map['car_id'] as String,
      title: map['title'] as String,
      body: map['body'] as String?,
      category: map['category'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      media: media,
      linkedModLabel: _labelFromLinked(linked),
      linkedCategory: linked?['category'] as String?,
    );
  }
}
