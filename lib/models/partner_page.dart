/// A partner's public page. Mirrors the `partner_pages` table.
class PartnerPage {
  const PartnerPage({
    required this.id,
    required this.ownerId,
    required this.businessName,
    this.bio,
    this.bannerUrl,
    this.websiteUrl,
    required this.createdAt,
  });

  final String id;
  final String ownerId;
  final String businessName;
  final String? bio;
  final String? bannerUrl;
  final String? websiteUrl;
  final DateTime createdAt;

  bool get hasBanner => bannerUrl != null && bannerUrl!.trim().isNotEmpty;
  bool get hasWebsite => websiteUrl != null && websiteUrl!.trim().isNotEmpty;

  factory PartnerPage.fromMap(Map<String, dynamic> map) {
    return PartnerPage(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      businessName: (map['business_name'] as String?) ?? 'Partner',
      bio: map['bio'] as String?,
      bannerUrl: map['banner_url'] as String?,
      websiteUrl: map['website_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
