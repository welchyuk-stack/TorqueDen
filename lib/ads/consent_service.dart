import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Gathers the consent required before any ad is requested, then initialises
/// the Mobile Ads SDK. Two separate layers apply:
///
///  1. **Google UMP** (User Messaging Platform, bundled with `google_mobile_ads`)
///     — the GDPR / UK-GDPR consent form shown to EEA + UK users. Required
///     before serving personalised ads. Outside those regions the form usually
///     isn't shown and ads can be requested straight away.
///  2. **Apple ATT** (App Tracking Transparency) — the iOS system prompt asking
///     permission to use the advertising identifier (IDFA). iOS only.
///
/// Call [ensureReady] at app start and again from anything about to show an ad;
/// the work runs exactly once (subsequent calls await the same future). Read
/// [canRequestAds] before loading an ad — it reflects the UMP SDK's decision, so
/// a user who declines in the EEA/UK simply gets no ad.
class ConsentService {
  ConsentService._();
  static final ConsentService instance = ConsentService._();

  Future<void>? _pending;
  bool _canRequestAds = false;

  /// Whether an ad may be requested yet (consent resolved or not required).
  bool get canRequestAds => _canRequestAds;

  /// Runs the consent flow once; completes when ad requests are permitted.
  Future<void> ensureReady() => _pending ??= _run();

  Future<void> _run() async {
    // 1. UMP: refresh consent info and show the form where the region requires
    //    it. Failures fall through — we still init ads (non-personalised).
    try {
      await _gatherUmpConsent();
    } catch (_) {/* carry on with whatever consent state we have */}

    // 2. Apple ATT prompt (iOS only; no-op elsewhere). Only prompt once.
    if (Platform.isIOS) {
      try {
        final status = await AppTrackingTransparency.trackingAuthorizationStatus;
        if (status == TrackingStatus.notDetermined) {
          await AppTrackingTransparency.requestTrackingAuthorization();
        }
      } catch (_) {/* prompt unavailable — carry on */}
    }

    // 3. Ask the UMP SDK whether ads may now be requested.
    try {
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
    } catch (_) {
      _canRequestAds = true; // e.g. non-EEA / SDK error → default open
    }

    // 4. Consent resolved — safe to initialise the Mobile Ads SDK.
    await MobileAds.instance.initialize();
  }

  Future<void> _gatherUmpConsent() {
    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        // Consent info updated — show the form if the user's region needs it.
        ConsentForm.loadAndShowConsentFormIfRequired((FormError? _) {
          if (!completer.isCompleted) completer.complete();
        });
      },
      (FormError _) {
        if (!completer.isCompleted) completer.complete();
      },
    );
    return completer.future;
  }

  /// Whether a persistent "privacy options" entry point must be offered (EEA/UK
  /// users who can revisit their consent). Gate a Settings tile on this.
  Future<bool> isPrivacyOptionsRequired() async {
    try {
      final status =
          await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
      return status == PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  /// Re-opens the consent form so a user can change their ad-consent choices.
  Future<void> showPrivacyOptionsForm() {
    final completer = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((FormError? _) {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }
}
