import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:torqueden/ads/ad_ids.dart';
import 'package:torqueden/ads/consent_service.dart';
import 'package:torqueden/theme.dart';

/// A single AdMob medium-rectangle (300×250) ad woven into the feed, wrapped in
/// the same card chrome and clearly labelled "Ad". Renders nothing until the
/// ad loads, and self-heals on failure (takes no space if it can't fill).
class FeedAdSlot extends StatefulWidget {
  const FeedAdSlot({super.key});

  @override
  State<FeedAdSlot> createState() => _FeedAdSlotState();
}

class _FeedAdSlotState extends State<FeedAdSlot> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadWhenConsented();
  }

  /// Wait for the consent flow (UMP + ATT) to resolve, then only request an ad
  /// if consent permits it. A user who declines in the EEA/UK gets no ad.
  Future<void> _loadWhenConsented() async {
    await ConsentService.instance.ensureReady();
    if (!mounted || !ConsentService.instance.canRequestAds) return;
    _ad = BannerAd(
      adUnitId: AdIds.feedBanner,
      size: AdSize.mediumRectangle, // 300x250
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() { _ad = null; _loaded = false; });
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.graphiteRaised,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Text('Ad',
                style: GoogleFonts.inter(
                    fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: AppColors.textMuted)),
          ),
          const SizedBox(height: 10),
          Center(
            child: SizedBox(
              width: AdSize.mediumRectangle.width.toDouble(),
              height: AdSize.mediumRectangle.height.toDouble(),
              child: AdWidget(ad: _ad!),
            ),
          ),
        ],
      ),
    );
  }
}
