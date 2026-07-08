import 'dart:io' show Platform;

/// AdMob identifiers. Uses Google's official **test** IDs while [useTestAds] is
/// true so ads render without an AdMob account and without risking policy
/// strikes. Before release: create an AdMob account, register the app + ad
/// units, paste the real IDs below, and set [useTestAds] = false. The app IDs
/// also live in ios/Runner/Info.plist (GADApplicationIdentifier) and
/// android AndroidManifest (com.google.android.gms.ads.APPLICATION_ID) — swap
/// those too.
class AdIds {
  AdIds._();

  static const bool useTestAds = false;

  // Google sample/test banner unit IDs (serve test ads for any size).
  static const String _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';
  static const String _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';

  // Real TorqueDen feed MREC (300x250) banner unit. iOS is live; Android is
  // parked, so its real ID is still a placeholder.
  static const String _realBannerIos = 'ca-app-pub-5912511696757213/5082751920';
  static const String _realBannerAndroid = 'ca-app-pub-0000000000000000/0000000000';

  static String get feedBanner {
    if (useTestAds) return Platform.isIOS ? _testBannerIos : _testBannerAndroid;
    return Platform.isIOS ? _realBannerIos : _realBannerAndroid;
  }
}
