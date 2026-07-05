/// RevenueCat + store configuration for in-app purchases (iOS-first; Android
/// parked). All the values below come from the RevenueCat dashboard and must
/// match what you set up there. See PURCHASES-SETUP.md for the full checklist.
class IapConfig {
  IapConfig._();

  /// RevenueCat **public** SDK key for Apple (Project → API keys → App Store;
  /// starts with `appl_`). Safe to ship in the app — it's not the secret key.
  /// TODO: paste the real key before release.
  static const String appleApiKey = 'appl_REPLACE_WITH_REVENUECAT_APPLE_KEY';

  /// True once a real key is present. While false, IAP init is skipped and the
  /// Membership screen falls back to its "coming soon" presentation, so the app
  /// runs normally before RevenueCat/App Store products exist.
  static bool get isConfigured =>
      appleApiKey.isNotEmpty && !appleApiKey.contains('REPLACE');

  /// Entitlement identifiers configured in RevenueCat (Project → Entitlements).
  /// The webhook and client both key off these.
  static const String premiumEntitlement = 'premium';
  static const String partnerEntitlement = 'partner';

  /// Fallback offering id (Project → Offerings). The app uses the *current*
  /// offering; this is only used if no current offering is marked.
  static const String premiumOffering = 'premium';
}
