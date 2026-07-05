import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/theme.dart';

/// Membership tiers. Users upgrade here via in-app purchase.
///
/// Purchases aren't wired yet (no StoreKit/IAP layer) and the user's tier isn't
/// tracked server-side, so this is currently a presentation of the tiers:
/// Free is shown as the current plan and the upgrade CTAs flag that purchasing
/// is coming soon. Pricing is TBD.
class MembershipScreen extends StatelessWidget {
  const MembershipScreen({super.key});

  void _comingSoon(BuildContext context, String tier) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$tier — in-app purchases are coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Membership')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              'Choose how you ride with TorqueDen. Pricing is being finalised — '
              'upgrades will land soon.',
              style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14, height: 1.45),
            ),
            const SizedBox(height: 20),
            _TierCard(
              name: 'Free',
              tagline: 'With ads',
              price: 'Free',
              current: true,
              features: const [
                'One car in your garage',
                'Join any club + create one public club',
                'Full feed & clubs access',
              ],
              onTap: null,
            ),
            const SizedBox(height: 14),
            _TierCard(
              name: 'Premium',
              tagline: 'No ads',
              price: 'Pricing TBD',
              highlight: true,
              features: const [
                'No ads in your feed',
                'Unlimited cars in your garage',
                'Unlimited clubs — including private',
              ],
              ctaLabel: 'Upgrade',
              onTap: () => _comingSoon(context, 'Premium'),
            ),
            const SizedBox(height: 14),
            _TierCard(
              name: 'Partner',
              tagline: 'Marketplace access',
              price: 'Pricing TBD',
              features: const [
                'Everything in Premium',
                'Access the TorqueDen marketplace',
                'Sell as a brand, supplier or individual',
              ],
              ctaLabel: 'Get in touch',
              onTap: () => _comingSoon(context, 'Partner'),
            ),
            const SizedBox(height: 20),
            Text(
              'Payments are handled securely through the App Store. You can manage '
              'or cancel a subscription anytime in your device settings.',
              style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12, height: 1.45),
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
    this.highlight = false,
    this.ctaLabel,
    this.onTap,
  });

  final String name;
  final String tagline;
  final String price;
  final List<String> features;
  final bool current;
  final bool highlight;
  final String? ctaLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlight ? AppColors.ember : AppColors.hairline,
          width: highlight ? 1.5 : 1,
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
                        style: GoogleFonts.archivo(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.cream)),
                    const SizedBox(height: 2),
                    Text(tagline, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
                  ],
                ),
              ),
              if (current) const _Badge(label: 'Current plan', filled: false)
              else if (highlight) const _Badge(label: 'Recommended', filled: true),
            ],
          ),
          const SizedBox(height: 14),
          Text(price,
              style: GoogleFonts.archivo(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.cream)),
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
                        style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, height: 1.35)),
                  ),
                ],
              ),
            ),
          if (current) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: null,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.hairline),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: Text('Your current plan',
                    style: GoogleFonts.inter(color: AppColors.steel, fontWeight: FontWeight.w600)),
              ),
            ),
          ] else if (ctaLabel != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
                child: Text(ctaLabel!),
              ),
            ),
          ],
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
