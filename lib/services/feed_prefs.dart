import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local feed filter preferences. Persisted via SharedPreferences.
/// Changing either notifier causes the feed to re-filter without a reload.
class FeedPrefs {
  FeedPrefs._();

  static const _kMediaOnly = 'feed_media_only';
  static const _kHideShot = 'feed_hide_shot';

  /// When true, only show posts that have at least one image or video.
  static final mediaOnly = ValueNotifier<bool>(false);

  /// When true, suppress posts tagged with a Shot challenge tag.
  static final hideShot = ValueNotifier<bool>(false);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    mediaOnly.value = p.getBool(_kMediaOnly) ?? false;
    hideShot.value = p.getBool(_kHideShot) ?? false;
  }

  static Future<void> setMediaOnly(bool v) async {
    mediaOnly.value = v;
    (await SharedPreferences.getInstance()).setBool(_kMediaOnly, v);
  }

  static Future<void> setHideShot(bool v) async {
    hideShot.value = v;
    (await SharedPreferences.getInstance()).setBool(_kHideShot, v);
  }
}
