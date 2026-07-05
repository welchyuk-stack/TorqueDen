import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/iap/iap_config.dart';
import 'package:torqueden/services/entitlements.dart';

/// Thin wrapper over RevenueCat (`purchases_flutter`) for buying Premium.
///
/// The durable, server-authoritative tier is written to `user_entitlements` by
/// the RevenueCat webhook (a Supabase Edge Function) — see
/// supabase/functions/revenuecat-webhook. This client layer just: configures
/// the SDK, ties the RevenueCat user to the Supabase uid (so the webhook can
/// find the right row), fetches offerings, runs purchases/restores, and nudges
/// [Entitlements] so gated UI updates immediately (the webhook + [Entitlements.refresh]
/// reconcile the real value shortly after).
class IapService {
  IapService._();
  static final IapService instance = IapService._();

  bool _configured = false;

  /// Whether IAP is wired (a real RevenueCat key is present). Until then the
  /// Membership screen shows its "coming soon" fallback.
  bool get isAvailable => _configured;

  /// Configure the RevenueCat SDK. No-op until a real key is set, so it's safe
  /// to call at startup. Identifies the current user if already logged in.
  Future<void> configure() async {
    if (_configured || !IapConfig.isConfigured) return;
    try {
      await Purchases.setLogLevel(LogLevel.info);
      final config = PurchasesConfiguration(IapConfig.appleApiKey);
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) config.appUserID = uid;
      await Purchases.configure(config);
      Purchases.addCustomerInfoUpdateListener(_apply);
      _configured = true;
    } catch (_) {
      // SDK unavailable (e.g. desktop) — leave IAP off; app runs fine.
    }
  }

  /// Tie the RevenueCat app-user to the Supabase uid so the webhook maps the
  /// purchase to the right `user_entitlements` row. Call on login.
  Future<void> identify(String uid) async {
    if (!_configured) return;
    try {
      final result = await Purchases.logIn(uid);
      _apply(result.customerInfo);
    } catch (_) {}
  }

  /// Detach the RevenueCat user on logout.
  Future<void> signOut() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } catch (_) {}
  }

  /// The offering holding the Premium packages (monthly/annual), or null if
  /// unavailable / not configured.
  Future<Offering?> premiumOffering() async {
    if (!_configured) return null;
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current ??
          offerings.getOffering(IapConfig.premiumOffering);
    } catch (_) {
      return null;
    }
  }

  /// Buy a package. Returns true if the user is entitled afterwards. A user
  /// cancel returns false quietly; other store errors rethrow for the UI.
  Future<bool> purchase(Package package) async {
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _apply(result.customerInfo);
      return _isEntitled(result.customerInfo);
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) ==
          PurchasesErrorCode.purchaseCancelledError) {
        return false;
      }
      rethrow;
    }
  }

  /// Restore prior purchases (required by App Store review). Returns true if
  /// the restore left the user entitled.
  Future<bool> restore() async {
    if (!_configured) return false;
    final info = await Purchases.restorePurchases();
    _apply(info);
    return _isEntitled(info);
  }

  bool _isEntitled(CustomerInfo info) =>
      info.entitlements.active.containsKey(IapConfig.premiumEntitlement) ||
      info.entitlements.active.containsKey(IapConfig.partnerEntitlement);

  /// Map RevenueCat's active entitlements onto the cached tier for immediate
  /// UI. We never downgrade to free here — the server (webhook + refresh) owns
  /// removals, so a transient empty update can't wrongly lock a paying user out.
  void _apply(CustomerInfo info) {
    final active = info.entitlements.active.keys.toSet();
    if (active.contains(IapConfig.partnerEntitlement)) {
      Entitlements.applyPurchasedTier(Tier.partner);
    } else if (active.contains(IapConfig.premiumEntitlement)) {
      Entitlements.applyPurchasedTier(Tier.premium);
    }
  }
}
