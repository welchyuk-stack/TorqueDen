import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:torqueden/screens/about_screen.dart' show kAppVersion;

/// Requests an App Store review at a positive moment (after the user's Nth
/// content post), gated so we only prompt once per app version. Apple's native
/// prompt (SKStoreReviewController) is itself rate-limited (~3/year) and may
/// decline to show — so this is best-effort by design; never block on it.
class ReviewService {
  ReviewService._();

  static const _kCount = 'review_positive_events';
  static const _kAskedVersion = 'review_asked_version';
  static const _threshold = 2; // ask after the 2nd positive event

  /// Record a positive moment; request a review once the threshold is reached
  /// (once per app version). Safe to fire-and-forget.
  static Future<void> recordPositiveEvent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt(_kCount) ?? 0) + 1;
      await prefs.setInt(_kCount, count);
      if (count < _threshold) return;
      if (prefs.getString(_kAskedVersion) == kAppVersion) return; // asked this version
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await prefs.setString(_kAskedVersion, kAppVersion);
        await review.requestReview();
      }
    } catch (_) {
      // Reviews are best-effort — never surface an error.
    }
  }
}
