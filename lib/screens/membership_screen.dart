import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:torqueden/iap/iap_service.dart';
import 'package:torqueden/services/entitlements.dart';
import 'package:torqueden/support_links.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/utils/open_link.dart';

/// Membership tiers. Premium is sold via RevenueCat (auto-renewable
/// subscription); Partner is held as "coming soon" while the userbase builds.
///
/// If IAP isn't wired yet (no RevenueCat key / no offerings), the Premium card
/// falls back to a "coming soon" presentation so the screen still works.
class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  Offering? _offering;
  bool _loading = true;
  bool _busy = false; // a purchase/restore is in flight

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Entitlements.refresh();
    final offering = await IapService.instance.premiumOffering();
    if (!mounted) return;
    setState(() {
      _offering = offering;
      _loading = false;
    });
  }

  /// Premium packages to show, annual first (best value), then monthly.
  List<Package> get _premiumPackages {
    final o = _offering;
    if (o == null) return const [];
    final preferred = <Package?>[o.annual, o.monthly].whereType<Package>().toList();
    return preferred.isEmpty ? o.availablePackages : preferred;
  }

  bool get _iapReady => IapService.instance.isAvailable && _premiumPackages.isNotEmpty;

  Future<void> _buy(Package pkg) async {
    setState(() => _busy = true);
    try {
      final ok = await IapService.instance.purchase(pkg);
      if (!mounted) return;
      if (ok) {
        await Entitlements.refresh(); // pick up the server tier if it landed
        if (!mounted) return;
        _snack('Welcome to Premium! 🎉');
      }
    } catch (_) {
      if (mounted) _snack('Purchase couldn\'t be completed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final ok = await IapService.instance.restore();
      if (ok) await Entitlements.refresh();
      if (!mounted) return;
      _snack(ok ? 'Purchases restored.' : 'No purchases to restore.');
    } catch (_) {
      if (mounted) _snack('Couldn\'t restore purchases.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _comingSoon(String tier) => _snack('$tier — coming soon.');

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  String _packageLabel(Package p) => switch (p.packageType) {
        PackageType.annual => 'Annual',
        PackageType.monthly => 'Monthly',
        PackageType.weekly => 'Weekly',
        PackageType.sixMonth => '6 months',
        PackageType.threeMonth => '3 months',
        PackageType.twoMonth => '2 months',
        PackageType.lifetime => 'Lifetime',
        _ => p.storeProduct.title,
      };

  @override
  Widget build(BuildContext context) {
    final isPremium = Entitlements.isPremium; // premium or partner
    return Scaffold(
      appBar: AppBar(title: const Text('Membership')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Text(
                    'Choose how you ride with TorqueDen.',
                    style: GoogleFonts.inter(
                        color: AppColors.textSecondary, fontSize: 14, height: 1.45),
                  ),
                  const SizedBox(height: 20),
                  _TierCard(
                    name: 'Free',
                    tagline: 'With ads',
                    price: 'Free',
                    current: !isPremium,
                    features: const [
                      'One car in your garage',
                      'Join any club + create one public club',
                      'Full feed & clubs access',
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildPremiumCard(isPremium),
                  const SizedBox(height: 14),
                  _TierCard(
                    name: 'Partner',
                    tagline: 'Business promotion',
                    price: 'Coming soon',
                    comingSoon: true,
                    features: const [
                      'Everything in Premium',
                      'Add your business website & profile',
                      'Sell your products into the userbase',
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_iapReady && !isPremium)
                    Center(
                      child: TextButton(
                        onPressed: _busy ? null : _restore,
                        child: Text('Restore purchases',
                            style: GoogleFonts.inter(color: AppColors.steel, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _legalFooter(),
                ],
              ),
      ),
    );
  }

  // Planned launch prices, shown as a preview before RevenueCat is wired. Once
  // IAP is live the real (localized) App Store prices from the offering replace
  // these. Keep in sync with the pricing plan.
  static const _plannedAnnualLabel = 'Annual · £24.99/yr';
  static const _plannedMonthlyLabel = 'Monthly · £2.99/mo';
  static const _plannedHeadline = 'From £2.99/mo';

  Widget _buildPremiumCard(bool isPremium) {
    final packages = _premiumPackages;
    final buttons = <_PurchaseButton>[];
    if (!isPremium) {
      if (_iapReady) {
        // Live store packages — real prices, real purchases.
        for (final p in packages) {
          buttons.add(_PurchaseButton(
            label: '${_packageLabel(p)} · ${p.storeProduct.priceString}',
            onPressed: _busy ? null : () => _buy(p),
          ));
        }
      } else {
        // Pre-IAP preview: planned prices; tapping explains it's coming.
        buttons.addAll([
          _PurchaseButton(label: _plannedAnnualLabel, onPressed: _busy ? null : () => _comingSoon('Premium')),
          _PurchaseButton(label: _plannedMonthlyLabel, onPressed: _busy ? null : () => _comingSoon('Premium')),
        ]);
      }
    }
    return _TierCard(
      name: 'Premium',
      tagline: 'No ads',
      price: _iapReady ? _premiumHeadlinePrice(packages) : _plannedHeadline,
      highlight: true,
      current: isPremium,
      features: const [
        'No ads in your feed',
        'Unlimited cars in your garage',
        'Unlimited clubs — including private',
      ],
      purchaseButtons: buttons.isEmpty ? null : buttons,
      busy: _busy,
    );
  }

  String _premiumHeadlinePrice(List<Package> packages) {
    if (packages.isEmpty) return 'Pricing TBD';
    // Show the annual if present (headline value), else the first package.
    final annual = packages.firstWhere(
      (p) => p.packageType == PackageType.annual,
      orElse: () => packages.first,
    );
    return annual.storeProduct.priceString;
  }

  Widget _legalFooter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payments are handled securely through the App Store. Subscriptions '
          'renew automatically until cancelled; manage or cancel anytime in your '
          'device settings.',
          style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12, height: 1.45),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _footerLink('Terms of Service', SupportLinks.termsUrl),
            Text('·', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
            _footerLink('Privacy Policy', SupportLinks.privacyPolicyUrl),
          ],
        ),
      ],
    );
  }

  Widget _footerLink(String label, String url) => GestureDetector(
        onTap: () => openLink(context, url),
        child: Text(label,
            style: GoogleFonts.inter(
                color: AppColors.ember, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

/// A single purchase option (label + price) rendered as a full-width button.
class _PurchaseButton {
  const _PurchaseButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;
}

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.name,
    required this.tagline,
    required this.price,
    required this.features,
    this.current = false,
    this.highlight = false,
    this.comingSoon = false,
    this.purchaseButtons,
    this.busy = false,
  });

  final String name;
  final String tagline;
  final String price;
  final List<String> features;
  final bool current;
  final bool highlight;
  final bool comingSoon;
  final List<_PurchaseButton>? purchaseButtons;
  final bool busy;

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
              else if (comingSoon) const _Badge(label: 'Coming soon', filled: false)
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
          ] else if (comingSoon) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: null,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.hairline),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: Text('Coming soon',
                    style: GoogleFonts.inter(color: AppColors.steel, fontWeight: FontWeight.w600)),
              ),
            ),
          ] else if (purchaseButtons != null && purchaseButtons!.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final b in purchaseButtons!)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: b.onPressed,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
                    child: busy
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(b.label),
                  ),
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
