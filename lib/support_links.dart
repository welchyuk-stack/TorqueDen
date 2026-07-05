/// External support / outbound links used by the Settings screens.
///
/// TODO: replace the placeholders below with real values.
///   • [supportEmail]   — the inbox Contact us & Feedback sends to
///   • [paypalDonateUrl]— your PayPal.Me (or PayPal donate) link
///   • [appStoreUrl]    — the App Store listing (once published)
///   • [playStoreUrl]   — the Play Store listing (once published)
class SupportLinks {
  SupportLinks._();

  static const String supportEmail = 'support@torqueden.app';
  static const String paypalDonateUrl = 'https://www.paypal.com/paypalme/torqueden';
  static const String appStoreUrl = 'https://apps.apple.com/app/torqueden/id0000000000';
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.torqueden.app';

  // Hosted legal pages (docs/ served via GitHub Pages). Update the base if the
  // hosting location changes.
  static const String _policiesBase = 'https://welchyuk-stack.github.io/TorqueDen';
  static const String privacyPolicyUrl = '$_policiesBase/privacy-policy.html';
  static const String termsUrl = '$_policiesBase/terms-of-service.html';
  static const String communityGuidelinesUrl = '$_policiesBase/community-guidelines.html';
}
