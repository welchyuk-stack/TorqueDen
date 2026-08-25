import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

import 'package:torqueden/models/car.dart';

const _shareCardsPublicBucket = 'share-cards';
const _publicBaseUrl = 'https://torqueden.app/c';

class ShareService {
  ShareService._();
  static final instance = ShareService._();

  final _client = Supabase.instance.client;

  // ── Slug ─────────────────────────────────────────────────────────────────

  /// Returns the existing slug for [car], or generates and persists a new one.
  Future<String> ensureSlug(Car car) async {
    if (car.publicSlug != null && car.publicSlug!.isNotEmpty) {
      return car.publicSlug!;
    }
    for (var attempt = 0; attempt < 5; attempt++) {
      final slug = _buildSlug(car);
      try {
        await _client
            .from('cars')
            .update({'public_slug': slug})
            .eq('id', car.id);
        return slug;
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow; // 23505 = unique_violation; retry
      }
    }
    throw Exception('Could not generate a unique share slug after 5 attempts');
  }

  String _buildSlug(Car car) {
    final base = (car.nickname?.trim().isNotEmpty == true
            ? car.nickname!.trim()
            : '${car.make} ${car.model}')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return '$base-${_randomSuffix(4)}';
  }

  String _randomSuffix(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ── Card capture ──────────────────────────────────────────────────────────

  /// Captures the widget bound to [key] as a PNG at [pixelRatio] scale.
  /// The [RepaintBoundary] wrapping the widget must already be rendered.
  Future<Uint8List> captureCard(GlobalKey key, {double pixelRatio = 3.0}) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('Share card not yet rendered');
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  // ── Upload ────────────────────────────────────────────────────────────────

  /// Uploads [pngBytes] to the public `share-cards` bucket at `{carId}.png`.
  Future<void> uploadCard(String carId, Uint8List pngBytes) async {
    await _client.storage.from(_shareCardsPublicBucket).uploadBinary(
          '$carId.png',
          pngBytes,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: true,
          ),
        );
  }

  /// Returns the public CDN URL for a car's share card.
  String cardPublicUrl(String carId) {
    return _client.storage
        .from(_shareCardsPublicBucket)
        .getPublicUrl('$carId.png');
  }

  // ── Share invocations ─────────────────────────────────────────────────────

  /// Opens the native share sheet with the card image.
  Future<void> shareImage(Uint8List pngBytes, String carTitle) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/torqueden_share.png');
    await file.writeAsBytes(pngBytes);
    // Let exceptions propagate — callers display the error to the user.
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: 'Check out my $carTitle build on TorqueDen',
      ),
    );
  }

  /// Opens the native share sheet with the public car link.
  /// Falls back to clipboard if the share plugin isn't available.
  Future<bool> shareLink(String slug, String carTitle) async {
    final url = '$_publicBaseUrl/$slug';
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: 'Check out my $carTitle build on TorqueDen: $url',
        ),
      );
      return false;
    } catch (_) {
      // Fallback: copy to clipboard.
      await Clipboard.setData(ClipboardData(text: url));
      return true;
    }
  }

  // ── Toggle ────────────────────────────────────────────────────────────────

  Future<void> setShareEnabled(String carId, {required bool enabled}) async {
    await _client
        .from('cars')
        .update({'share_enabled': enabled})
        .eq('id', carId);
  }

  /// Public share URL for a known slug.
  static String urlForSlug(String slug) => '$_publicBaseUrl/$slug';
}
