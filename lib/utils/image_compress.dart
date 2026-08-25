import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Converts a raw Supabase storage URL into a resized/compressed render URL.
/// Pass [width] to match the largest dimension you'll display.
/// Falls back to the original URL for non-Supabase URLs.
String supabaseThumb(String url, {int width = 600, int quality = 75}) {
  final t = url.replaceFirst(
    '/storage/v1/object/public/',
    '/storage/v1/render/image/public/',
  );
  if (t == url) return url; // not a Supabase storage URL
  return '$t?width=$width&quality=$quality&resize=contain';
}

const _kMaxBytes = 200 * 1024; // skip if already under 200 KB
const _kMaxDimension = 1600;   // longest edge cap
const _kQuality = 82;          // JPEG quality

/// Compresses [bytes] to JPEG at most [_kMaxDimension] on the longest edge
/// and [_kQuality]% quality. Runs in a background isolate. Returns [bytes]
/// unchanged if already under [_kMaxBytes] or decoding fails.
Future<Uint8List> compressImageBytes(Uint8List bytes) async {
  if (bytes.length <= _kMaxBytes) return bytes;
  return compute(_compress, bytes);
}

Uint8List _compress(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return bytes;

  img.Image out = image;
  if (image.width > _kMaxDimension || image.height > _kMaxDimension) {
    out = image.width >= image.height
        ? img.copyResize(image, width: _kMaxDimension)
        : img.copyResize(image, height: _kMaxDimension);
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: _kQuality));
}
