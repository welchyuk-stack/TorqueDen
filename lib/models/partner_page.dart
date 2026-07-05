/// Aspect ratio for partner banners — a wide strip, used everywhere the banner
/// appears (framer, edit preview, partner page, and the directory card) so the
/// whole banner shows without cropping.
const double kBannerAspect = 16 / 4.5;

/// A partner's public page. Mirrors the `partner_pages` table.
class PartnerPage {
  const PartnerPage({
    required this.id,
    required this.ownerId,
    required this.businessName,
    this.bio,
    this.bannerUrl,
    this.websiteUrl,
    this.address,
    this.contactEmail,
    required this.createdAt,
  });

  final String id;
  final String ownerId;
  final String businessName;
  final String? bio;
  final String? bannerUrl;
  final String? websiteUrl;
  final String? address;
  final String? contactEmail;
  final DateTime createdAt;

  bool get hasBanner => bannerUrl != null && bannerUrl!.trim().isNotEmpty;
  bool get hasWebsite => websiteUrl != null && websiteUrl!.trim().isNotEmpty;
  bool get hasAddress => address != null && address!.trim().isNotEmpty;
  bool get hasEmail => contactEmail != null && contactEmail!.trim().isNotEmpty;

  factory PartnerPage.fromMap(Map<String, dynamic> map) {
    return PartnerPage(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      businessName: (map['business_name'] as String?) ?? 'Partner',
      bio: map['bio'] as String?,
      bannerUrl: map['banner_url'] as String?,
      websiteUrl: map['website_url'] as String?,
      address: map['address'] as String?,
      contactEmail: map['contact_email'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
