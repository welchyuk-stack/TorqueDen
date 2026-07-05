import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/theme.dart';

/// Membership tiers. While we build the userbase, TorqueDen is free (with ads)
/// and everything is unlocked. Partner (for businesses) is held as "coming
/// soon"; a paid Premium tier may return once there's an audience to justify it.
class MembershipScreen extends StatelessWidget {
  const MembershipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Membership')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: const [
            _TierCard(
              name: 'Free',
              tagline: 'Everything, with ads',
              price: 'Free',
              current: true,
              features: [
                'Unlimited cars in your garage',
                'Create unlimited clubs — public or private',
                'Full feed, clubs & Discover',
                'Supported by ads',
              ],
            ),
            SizedBox(height: 14),
            _TierCard(
              name: 'Partner',
              tagline: 'Business promotion',
              price: 'Coming soon',
              comingSoon: true,
              features: [
                'Add your business website & profile',
                'Offer your products and services to the userbase',
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.name,
    required this.tagline,
    required this.price,
    required this.features,
    this.current = false,
    this.comingSoon = false,
  });

  final String name;
  final String tagline;
  final String price;
  final List<String> features;
  final bool current;
  final bool comingSoon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: current ? AppColors.ember : AppColors.hairline,
          width: current ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: GoogleFonts.archivo(
                            fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.cream)),
                    const SizedBox(height: 2),
                    Text(tagline, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
                  ],
                ),
              ),
              if (current)
                const _Badge(label: 'Current plan', filled: false)
              else if (comingSoon)
                const _Badge(label: 'Coming soon', filled: false),
            ],
          ),
          const SizedBox(height: 14),
          Text(price,
              style: GoogleFonts.archivo(
                  fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.cream)),
          const SizedBox(height: 14),
          for (final f in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle, size: 16, color: AppColors.ember),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(f,
                        style: GoogleFonts.inter(
                            fontSize: 14, color: AppColors.textSecondary, height: 1.35)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.filled});
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? AppColors.ember : AppColors.ember.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: filled ? AppColors.onEmber : AppColors.ember,
        ),
      ),
    );
  }
}
