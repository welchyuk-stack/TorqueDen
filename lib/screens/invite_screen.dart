import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:torqueden/support_links.dart';
import 'package:torqueden/theme.dart';

/// Invite friends — copies a store link (App Store on iOS, Play Store on
/// Android) so users can share TorqueDen.
class InviteScreen extends StatelessWidget {
  const InviteScreen({super.key});

  /// The right store link for this device.
  String get _link {
    if (Platform.isAndroid) return SupportLinks.playStoreUrl;
    return SupportLinks.appStoreUrl; // iOS (and a sensible default elsewhere)
  }

  String get _storeName => Platform.isAndroid ? 'Google Play' : 'the App Store';

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard.')),
    );
  }

  Future<void> _openStore(BuildContext context) async {
    try {
      final ok = await launchUrl(Uri.parse(_link), mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t open the store page.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t open the store page.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invite friends')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.ember.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.group_add_outlined, size: 44, color: AppColors.ember),
                ),
                const SizedBox(height: 24),
                Text('Bring your crew',
                    style: GoogleFonts.archivo(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.cream)),
                const SizedBox(height: 12),
                Text(
                  'Know someone with a build worth showing off? Share TorqueDen and '
                  'get them in the den.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 28),
                // The link, tappable to copy.
                InkWell(
                  onTap: () => _copy(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.graphiteRaised,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(_link,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13)),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.copy, size: 18, color: AppColors.steel),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _copy(context),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: const Icon(Icons.link, size: 20),
                    label: const Text('Copy invite link'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => _openStore(context),
                  child: Text('Open $_storeName',
                      style: GoogleFonts.inter(color: AppColors.ember, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
