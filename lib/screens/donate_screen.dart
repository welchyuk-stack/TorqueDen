import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:torqueden/support_links.dart';
import 'package:torqueden/theme.dart';

/// Donate — opens the app's PayPal link so people can chip in toward running
/// costs. Voluntary; separate from Premium membership.
class DonateScreen extends StatelessWidget {
  const DonateScreen({super.key});

  Future<void> _donate(BuildContext context) async {
    final uri = Uri.parse(SupportLinks.paypalDonateUrl);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t open PayPal. Please try again.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t open PayPal. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Donate')),
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
                  child: const Icon(Icons.volunteer_activism_outlined, size: 44, color: AppColors.ember),
                ),
                const SizedBox(height: 24),
                Text('Support TorqueDen',
                    style: GoogleFonts.archivo(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.cream)),
                const SizedBox(height: 12),
                Text(
                  'TorqueDen is built by a small team. If you\'d like to help cover '
                  'server and running costs, a donation goes a long way — and it\'s '
                  'completely optional.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _donate(context),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: const Icon(Icons.favorite, size: 20),
                    label: const Text('Donate with PayPal'),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Opens PayPal in your browser.',
                    style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
