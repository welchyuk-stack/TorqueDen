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

  static const bool useTestAds = true;

  // Google sample/test banner unit IDs (serve test ads for any size).
  static const String _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';
  static const String _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';

  // TODO: real ad unit IDs once the AdMob app is set up.
  static const String _realBannerIos = 'ca-app-pub-0000000000000000/0000000000';
  static const String _realBannerAndroid = 'ca-app-pub-0000000000000000/0000000000';

  static String get feedBanner {
    if (useTestAds) return Platform.isIOS ? _testBannerIos : _testBannerAndroid;
    return Platform.isIOS ? _realBannerIos : _realBannerAndroid;
  }
}
