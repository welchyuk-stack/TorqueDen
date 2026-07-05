import 'package:flutter/services.dart';

/// Trims a video natively (iOS AVFoundation via a method channel — no ffmpeg).
/// Returns the trimmed file's path, or null on failure / unsupported platform,
/// in which case the caller falls back to the original clip.
class VideoTrimService {
  VideoTrimService._();

  static const _channel = MethodChannel('torqueden/video');

  /// Trims to [start]..[end] and, if [filter] is set (a filter id like 'mono'),
  /// bakes in that colour filter — in a single native re-encode.
  static Future<String?> trim(
    String path,
    Duration start,
    Duration end, {
    String? filter,
  }) async {
    try {
      return await _channel.invokeMethod<String>('trim', {
        'path': path,
        'startMs': start.inMilliseconds,
        'endMs': end.inMilliseconds,
        'filter': ?filter,
      });
    } catch (_) {
      return null;
    }
  }

  /// A poster-frame JPEG for [path], or null on failure / unsupported platform.
  static Future<Uint8List?> thumbnail(String path) async {
    try {
      return await _channel.invokeMethod<Uint8List>('thumbnail', {'path': path});
    } catch (_) {
      return null;
    }
  }
}
