import 'package:supabase_flutter/supabase_flutter.dart';

/// Membership tier for the current user, read from `user_entitlements`.
enum Tier { free, premium, partner }

/// Gates Premium/Partner features. Tier is server-authoritative (clients can't
/// write it). Call [refresh] after login / when entering a gated surface, then
/// read the cached [tier] / feature getters.
class Entitlements {
  Entitlements._();

  /// Master switch for gating. While in-app purchases aren't live, this stays
  /// `false` so every user can use "Premium" features. Flip to `true` to
  /// actually enforce tiers (the one-line change to turn gating on).
  static const bool enforce = false;

  static Tier _tier = Tier.free;
  static Tier get tier => _tier;

  static bool get isPremium => _tier == Tier.premium || _tier == Tier.partner;
  static bool get isPartner => _tier == Tier.partner;

  /// Creating clubs is a Premium feature. Open to everyone while [enforce] is off.
  static bool get canCreateClubs => !enforce || isPremium;

  /// Creating/editing a Partner Page always requires the Partner tier — there's
  /// no free-trial concept for a B2B page, so this ignores [enforce]. (RLS also
  /// enforces it server-side.)
  static bool get canManagePartnerPage => isPartner;

  static Future<void> refresh() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) { _tier = Tier.free; return; }
    try {
      final row = await Supabase.instance.client
          .from('user_entitlements')
          .select('tier')
          .eq('user_id', uid)
          .maybeSingle();
      _tier = _parse(row?['tier'] as String?);
    } catch (_) {
      _tier = Tier.free; // absence / error → free
    }
  }

  static Tier _parse(String? s) => switch (s) {
        'premium' => Tier.premium,
        'partner' => Tier.partner,
        _ => Tier.free,
      };
}
