import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/build_entry.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/services/share_service.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/share_card_view.dart';

/// Two-option share bottom sheet: "Share as image" or "Share link".
/// Shows a live preview of the card being rendered.
///
/// Usage:
/// ```dart
/// showShareSheet(context, car: car);
/// ```
Future<void> showShareSheet(
  BuildContext context, {
  required Car car,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.graphiteRaised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ShareSheet(car: car),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.car});
  final Car car;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _cardKey = GlobalKey();
  final _svc = ShareService.instance;
  final _client = Supabase.instance.client;

  bool _rendering = false;
  bool _loadingLink = false;

  // Resolved slug — set once ensureSlug() resolves so the QR code
  // in the card preview updates before we capture it.
  String? _resolvedSlug;

  Car get _car => widget.car;

  // Fetch up to 4 recent build entries for the card headline mods.
  List<BuildEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    try {
      final rows = await _client
          .from('build_entries')
          .select('id, car_id, title, body, category, created_at, location_name, tags')
          .eq('car_id', _car.id)
          .order('created_at', ascending: false)
          .limit(4);
      if (mounted) {
        setState(() {
          _entries = (rows as List)
              .map((r) => BuildEntry.fromMap(r as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (_) {
      // Non-fatal — card renders without mods list.
    }
  }

  Future<String?> _ensureSlug() async {
    try {
      return await _svc.ensureSlug(_car);
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareImage() async {
    if (_rendering) return;
    setState(() => _rendering = true);
    String? lastError;
    try {
      // Precache car photo so the RepaintBoundary captures it fully loaded.
      if (_car.hasPhoto) {
        try {
          await precacheImage(NetworkImage(_car.photoUrl!), context)
              .timeout(const Duration(seconds: 6));
        } catch (_) {}
      }

      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      final bytes = await _svc.captureCard(_cardKey, pixelRatio: 4.0);

      // Share while sheet is still mounted — iOS presents over it fine.
      await _svc.shareImage(bytes, _car.title);

      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      debugPrint('ShareImage error: $e\n$st');
      lastError = e.toString();
    } finally {
      if (mounted) {
        setState(() => _rendering = false);
        if (lastError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Share failed: $lastError'),
              duration: const Duration(seconds: 8),
            ),
          );
        }
      }
    }
  }

  Future<void> _shareLink() async {
    if (_loadingLink) return;
    setState(() => _loadingLink = true);
    try {
      final slug = await _ensureSlug();
      if (slug == null) throw Exception('Could not generate link');

      // Upload card for og:image (fire-and-forget).
      _captureAndUpload(slug).ignore();

      final usedClipboard = await _svc.shareLink(slug, _car.title);
      if (mounted) {
        Navigator.of(context).pop();
        if (usedClipboard) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Link copied to clipboard')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate link: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingLink = false);
    }
  }

  Future<void> _captureAndUpload(String slug) async {
    try {
      if (_car.hasPhoto) {
        await precacheImage(NetworkImage(_car.photoUrl!), context);
      }
      await WidgetsBinding.instance.endOfFrame;
      final bytes = await _svc.captureCard(_cardKey);
      await _svc.uploadCard(_car.id, bytes);
    } catch (_) {
      // Best-effort; link still works, og:image just won't update.
    }
  }

  @override
  Widget build(BuildContext context) {
    final slug = _resolvedSlug ?? _car.publicSlug;
    final shareUrl = slug != null ? ShareService.urlForSlug(slug) : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sheet handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Text(
              'Share ${_car.title}',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.cream,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose how to share this build',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
            ),

            const SizedBox(height: 20),

            // Card preview — also the capture target (RepaintBoundary).
            // Rendered at 320px wide (landscape); captured at 4× → 1920×1200 px.
            Center(
              child: SizedBox(
                width: 320,
                height: 320 * (ShareCardView.cardH / ShareCardView.cardW),
                child: RepaintBoundary(
                  key: _cardKey,
                  child: ShareCardView(
                    car: _car,
                    recentEntries: _entries,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Share as image
            _SheetOption(
              icon: Icons.image_outlined,
              label: 'Share as image',
              description: 'Branded card — post to Stories, WhatsApp, anywhere',
              loading: _rendering,
              onTap: _shareImage,
            ),

            if (_car.shareEnabled) ...[
              const SizedBox(height: 12),
              _SheetOption(
                icon: Icons.link_outlined,
                label: 'Copy / share link',
                description: 'torqueden.app/c/… — paste in bio, Discord, or DMs',
                loading: _loadingLink,
                onTap: _shareLink,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        decoration: BoxDecoration(
          color: AppColors.graphite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hairline, width: 0.8),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.ember.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, color: AppColors.ember, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.cream,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.steel, size: 18),
          ],
        ),
      ),
    );
  }
}
