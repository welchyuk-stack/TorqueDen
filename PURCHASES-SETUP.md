# In-app purchases (IAP) — setup checklist

The code is fully scaffolded (RevenueCat + a Supabase webhook). Everything below
is dashboard/account work needed to make purchases actually run. iOS-first;
Android is parked. Nothing here can be completed until the **Apple Developer
Program** enrolment (Individual / sole trader) is active.

## How it fits together
```
App (IapService, purchases_flutter)
   └─ buys a package via RevenueCat, identified by the Supabase uid
RevenueCat  ── webhook ──▶  Supabase Edge Function (revenuecat-webhook)
                               └─ looks up the subscriber's live entitlements
                                  and upserts user_entitlements.tier (service role)
App reads user_entitlements via Entitlements.refresh()  ← server-authoritative
```
The client also reflects the tier optimistically right after purchase; the
webhook is the durable source of truth.

## 1. App Store Connect
- [ ] Create the app record for bundle id `com.torqueden.app`.
- [ ] Create an **auto-renewable subscription group** (e.g. "TorqueDen Premium").
- [ ] Add two subscriptions in that group:
  - `premium_monthly` — £2.99/mo
  - `premium_annual` — £24.99/yr
  (Prices per the pricing plan; adjust as needed. 7-day free trial as an intro offer.)
- [ ] Fill each subscription's localized display name, description, and review info.
- [ ] Generate an **App Store Connect App-Specific Shared Secret** (for RevenueCat).

## 2. RevenueCat dashboard
- [ ] Create a project; add the **App Store** app (bundle id + the shared secret).
- [ ] Copy the **public Apple SDK key** (`appl_…`) → paste into `lib/iap/iap_config.dart` (`appleApiKey`).
- [ ] Create an **Entitlement** with identifier `premium` (must match `IapConfig.premiumEntitlement`).
      (Add `partner` later when the Partner tier launches.)
- [ ] Create **Products** for `premium_monthly` and `premium_annual`, attach both to the `premium` entitlement.
- [ ] Create an **Offering** (marked *current*) with an **Annual** package and a **Monthly** package
      pointing at those products. (The app shows annual first.)
- [ ] Get a **secret REST API key** (`sk_…`) for the webhook function.

## 3. Supabase Edge Function (webhook)
- [ ] Deploy: `supabase functions deploy revenuecat-webhook --no-verify-jwt`
- [ ] Set secrets:
  - `supabase secrets set REVENUECAT_WEBHOOK_AUTH=<a-long-random-string>`
  - `supabase secrets set REVENUECAT_REST_API_KEY=<sk_… secret key>`
  - (`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.)
- [ ] In RevenueCat → **Integrations → Webhooks**: set the URL to the function's
      public URL and the **Authorization** header to `Bearer <REVENUECAT_WEBHOOK_AUTH>`.
- [ ] (Note: this project applies migrations via the Management API, not the CLI —
      but Edge Functions still deploy via the `supabase` CLI. No DB migration is
      needed; `user_entitlements` already exists, 0016.)

## 4. Flip it on
- [ ] Paste the real `appl_…` key into `IapConfig.appleApiKey`.
- [ ] Set `Entitlements.enforce = true` in `lib/services/entitlements.dart` to
      activate all tier gates (car limit, club limit, private clubs, ad-free).
- [ ] Test the full loop with an App Store **sandbox** account (free trial → buy →
      confirm `user_entitlements.tier` flips to `premium` → confirm ads disappear
      and limits lift → cancel → confirm it reverts).
- [ ] Verify **Restore purchases** works (App Store review requires it).

## Notes
- Apple Small Business Program → 15% commission (you qualify). Apple is merchant
  of record and handles UK VAT.
- To grant Premium manually before IAP is live (e.g. testing), use the SQL in
  migration 0016's comment.
- Manually granting `partner` still works for seeding founding partners while the
  Partner tier is "coming soon".
