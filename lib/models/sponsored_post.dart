/// A native sponsored post (house ad) shown in the Home feed. Mirrors the
/// `sponsored_posts` table.
class SponsoredPost {
  const SponsoredPost({
    required this.id,
    required this.advertiserName,
    required this.headline,
    required this.ctaLabel,
    required this.ctaUrl,
    this.advertiserAvatarUrl,
    this.body,
    this.mediaUrl,
    this.mediaKind,
    this.weight = 1,
    this.startsAt,
    this.endsAt,
  });

  final String id;
  final String advertiserName;
  final String headline;
  final String ctaLabel;
  final String ctaUrl;
  final String? advertiserAvatarUrl;
  final String? body;
  final String? mediaUrl;
  final String? mediaKind;
  final int weight;
  final DateTime? startsAt;
  final DateTime? endsAt;

  bool get hasMedia => mediaUrl != null && mediaUrl!.trim().isNotEmpty;
  bool get hasAvatar => advertiserAvatarUrl != null && advertiserAvatarUrl!.trim().isNotEmpty;

  /// Whether this ad is within its optional schedule window.
  bool isLiveAt(DateTime now) =>
      (startsAt == null || !now.isBefore(startsAt!)) &&
      (endsAt == null || !now.isAfter(endsAt!));

  factory SponsoredPost.fromMap(Map<String, dynamic> map) {
    DateTime? parse(dynamic v) => v == null ? null : DateTime.parse(v as String);
    return SponsoredPost(
      id: map['id'] as String,
      advertiserName: (map['advertiser_name'] as String?) ?? 'Sponsored',
      headline: (map['headline'] as String?) ?? '',
      ctaLabel: (map['cta_label'] as String?) ?? 'Learn more',
      ctaUrl: (map['cta_url'] as String?) ?? '',
      advertiserAvatarUrl: map['advertiser_avatar_url'] as String?,
      body: map['body'] as String?,
      mediaUrl: map['media_url'] as String?,
      mediaKind: map['media_kind'] as String?,
      weight: (map['weight'] as int?) ?? 1,
      startsAt: parse(map['starts_at']),
      endsAt: parse(map['ends_at']),
    );
  }
}
