# TorqueDen Web App — Feature-Parity Scoping Document

## What this covers

A scoped plan for building a full web version of TorqueDen — same features as the iOS/Android app, running in a browser. This is a genuinely large second product, not a "port a few screens" job, so this document lays out the full feature surface pulled directly from the app's codebase, an honest architecture recommendation, and a phased build plan rather than a single all-at-once estimate.

The one major advantage working in your favour: **the backend is already shared-ready.** TorqueDen's entire data layer is Supabase (Postgres + Auth + Storage + Edge Functions), already exposed over a public API with Row Level Security policies doing the access control. A web app talks to the *exact same* backend the mobile app does — same users, same data, same clubs, same posts, live and in sync from day one. You are not building a second backend.

---

## 1. Full feature inventory (from the current app)

Grouped by area, pulled from `lib/screens/`, `lib/widgets/`, `lib/services/`, `lib/iap/`, `lib/ads/`, and the Supabase schema.

**Auth & onboarding**
Sign up / log in / password reset (`auth_gate`, `auth_screen`, `set_new_password_screen`), biometric app-lock (mobile-only concept, no web equivalent needed).

**Core social / feed**
Home feed of build posts, emoji reactions (Fire / Clean / Sick / Insane on `post_likes`), comments (`post_comments`), follow/unfollow a specific car (`follows`), post creation with photo (`create_post_screen`, `camera_screen`), post viewer (`post_viewer_screen`). Note: video posting/trimming (`video_trim_screen`) exists in the codebase but is currently disabled behind a `Features.video` flag — the app shipped **photos-only** to keep bandwidth costs down, so this is not part of the live feature set to match.

**Garage & cars**
Multi-car garage per user (`garage_screen`), add/edit a car (`add_car_screen`), car detail page with three tabs — Build log by category (`build_tab`), Posts (`posts_tab`), Specs (`specs_tab`) — full spec sheet (`car_specs` table: label/value pairs, ordered), build-log entries grouped by category with linked follow-up entries (`build_entries`).

**Discover**
Search by make/model/chassis code, "Near me" geolocation-based discovery (`discover_screen`, fuzzed lat/long for privacy).

**Clubs**
Browse/join clubs (`clubs_screen`), club detail with threads (`club_detail_screen`, `club_threads`, `club_replies`, reply voting), create a club — public or private (`create_club_screen`), club management: admins, bans, mutes, pinned threads, rules, slow-mode, blocked words, archive (`club_manage_screen`, `club_members_screen`, and the `club_admin`/`club_bans`/`club_mutes`/`club_mod_log` tables), invites (`invite_screen`).

**Notifications**
In-app notification inbox + bell badge (`notifications_screen`, `notifications_list_screen`, `notification_bell`), push notifications via FCM (mobile-only; web push is a separate, optional build).

**Moderation & safety**
Report content/users (`reports` table, `moderation_sheet`), block users (`blocks` table), community guidelines and account-deletion flows already live on the marketing site.

**Monetization**
Free / Premium / Partner tiers (`user_entitlements`, `membership_screen`, `upgrade_sheet`), in-app purchases via RevenueCat (mobile-only IAP; web billing is a different system — Stripe, typically), partner business pages (`partner_page_screen`, `partner_page_manager_screen`, sponsored posts, banner upload/framing).

**Settings & account**
Profile edit, units preference, saved search location, theme (light/dark), notification prefs, data policies, delete account, donate, contact/about.

---

## 2. What doesn't translate directly to web

Being upfront about this now saves scope surprises later:

- **Biometric app-lock** — a mobile OS concept (Face ID/fingerprint). No direct web equivalent; browsers don't expose this. Skip, or substitute a "remember this device" session length setting.
- **Video posting** — not actually live in the app right now (disabled behind `Features.video`, launched photos-only), so it's correctly **out of scope** for the web app too. If/when video is switched back on in the app, revisit whether web needs it — browser video capture/trim is meaningfully more finicky cross-browser than Flutter's native APIs, especially on iOS Safari, so treat it as its own future phase rather than folding it into this plan.
- **RevenueCat IAP** — RevenueCat's mobile SDKs don't apply to web. A web Premium/Partner purchase flow needs Stripe (or RevenueCat's newer web billing product, which is less mature). This is a separate integration, not a reuse of existing code.
- **Push notifications** — Web Push exists (service workers) but is a distinct implementation from FCM mobile push, and Safari's support has historically lagged. Treat as optional, not assumed.

Everything else — feed, garage, clubs, discover, moderation, settings — maps cleanly onto the same Supabase tables and RLS policies already in production. With video off the table, **photo capture is the only camera-adjacent piece**, and that's just a file picker + `getUserMedia` for an optional in-browser photo snap — low risk, not the cross-browser minefield video would have been.

---

## 3. Recommended architecture

- **Framework:** Next.js (React) or SvelteKit — either works well with Supabase's JS client and has first-class static/SSR hosting. Next.js has the larger ecosystem if you ever want to hand this to another developer later.
- **Styling:** reuse the carbon/glass theme already built for the marketing site — same CSS variables, same visual language, so the web app and marketing site feel like one product.
- **Backend:** the existing Supabase project, unchanged. Same tables, same RLS policies (which already correctly scope what a signed-in user can read/write), same Edge Functions where needed (e.g. a web-billing webhook analogous to the existing RevenueCat one).
- **Hosting:** Vercel or Cloudflare Pages (both have generous free tiers for a pre-revenue app), on a subdomain like `app.torquedenapp.com`, DNS added the same way as the main site.
- **Auth:** Supabase Auth's own hosted flows (email/password, magic link) — same user table as mobile, so a user can sign up on web and log into the app with the same account, or vice versa.

This is a real second frontend on a shared backend — not a simple static site, and not something to fold into the current GitHub Pages marketing site (different tech entirely: that's hand-written static HTML, this needs a JS framework, build step, and its own hosting).

---

## 4. Phased build plan

Rather than one big-bang estimate, three phases — each one shippable and useful on its own, so you can stop after any phase and still have something real. (An earlier draft of this plan had a separate "media capture" phase built around video's cross-browser risk; since video isn't actually live in the app, that risk goes away and photo capture folds cleanly into Phase 2.)

**Phase 1 — Read-only companion (1–2 weeks)**
Log in, view your garage, view any public car's specs/build log/posts, view public clubs and threads, view your own profile. No posting, no writing. Proves out the Supabase-web connection and the visual theme. Lowest risk, fastest to a demo.

**Phase 2 — Full interaction (2–5 weeks)**
Add on top of Phase 1: post text + photo (file picker upload to Supabase Storage, plus an optional in-browser photo snap via `getUserMedia` — no video, matching the live app), comments, reactions, follow/unfollow, create/edit a car and its specs/build log, join clubs and post in threads, create a club, notifications inbox, settings/profile edit, report/block. This is full parity with the live (photos-only) app, short of payments — genuinely a complete standalone web community at this point.

**Phase 3 — Monetization + partner pages (1–2 weeks)**
Stripe-based web checkout for Premium/Partner (separate from RevenueCat, needs its own webhook, similar shape to the existing `revenuecat-webhook` function), partner page creation/management, sponsored post placement in the web feed.

**Rough total: 4–9 weeks of focused work** for full parity with the current (photos-only) app — meaningfully shorter than a video-inclusive plan would have been, since the riskiest, least-predictable piece (cross-browser video capture) simply isn't needed right now. If video gets switched back on in the app later, treat browser video support as its own follow-up phase rather than retrofitting it here.

---

## 5. Ongoing cost of maintaining two frontends

Worth naming explicitly: once this exists, every new feature you build going forward gets built twice (once in Flutter, once in the web framework) unless you deliberately choose to skip a web equivalent for some features. That's a permanent, recurring cost, not a one-time build cost — the plan above gets you to parity, but staying at parity is an ongoing decision each time you add something to the app.

---

## 6. Suggested next step

Given TorqueDen is still pre-launch, the strongest ROI order is probably: ship Phase 1 once the app itself is live and has real users, using it to validate whether people actually want a web experience before sinking 4–9 weeks into full parity. Happy to start scaffolding Phase 1 whenever you want to move on it.
