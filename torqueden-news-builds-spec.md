# TorqueDen: News & Builds — Technical Scope

*Adding a car news feed to TorqueDen (existing social/UGC app), blended with followed-builds content. Quiet feature launch, not a full app relaunch. Branding/visual design handled separately — this covers features and architecture only.*

---

## 1. Core Concept

Extend TorqueDen with a curated car news feed (racing, road cars, modified) that users can blend with the existing builds/UGC feed. Positioned as a new feature within TorqueDen, not a rebrand or pivot. Solves two problems at once: gives the app a constant content floor independent of community posting activity, and gives users a reason to open the app even on quiet UGC days.

---

## 2. Architecture — three backends, each doing the job it's suited for

**Decision: do not migrate TorqueDen's existing Supabase backend.** A full migration to Cloudflare would require rebuilding Auth (no Cloudflare equivalent), moving Postgres → D1 (capability step-down, real schema/query rework), and rebuilding any realtime features — high risk to a live app for no clear benefit. Instead:

| Backend | Handles | Why |
|---|---|---|
| **Supabase (existing, unchanged)** | Auth, user accounts, relational data, existing UGC/social features | Already working — don't touch what isn't broken |
| **Cloudflare R2** | Image/media storage (migrated from Supabase Storage) | Zero egress fees — directly fixes the current bandwidth overage problem |
| **Cloudflare Workers + D1** | News ingestion, clustering, news API | New, isolated — doesn't touch Supabase quota; better architectural fit for shared/cached feed content anyway |
| **Cloudflare Image Transformations** | On-the-fly compression/resizing for both news thumbnails and (optionally) TorqueDen's own user-uploaded images | Billed per unique transformation, not per request — cheap at TorqueDen's likely volume; free tier covers 5,000 unique transforms/month |

**Client-side implication:** the TorqueDen app calls two separate API endpoints — existing Supabase URL for social/UGC features, new Cloudflare Workers URL for news. Standard multi-backend pattern, no architectural conflict.

**R2 migration approach:** new image uploads point to R2 going forward; existing images in Supabase Storage migrated in the background without user-facing disruption. This is the direct fix for the current 5GB/month overage issue — isolated from the news feature build, can proceed independently/in parallel.

---

## 3. News Content Sources

*(Carried over from the earlier standalone scoping — same source list applies)*

### 3.1 Racing
F1, NASCAR, IndyCar (Motorsport.com, RaceFans, The Race), GT3/British GT (GT REPORT), Drifting (Formula DRIFT official blog, DRIFTING.com). WRC feed source still needs confirmation.

### 3.2 Road Cars
Major pubs (Motor1, Car and Driver, Motor Trend, Autoblog, Carscoops, Jalopnik, Autoweek, Hemmings, The Truth About Cars). JDM/German/American Muscle via tag-filtering major-pub feeds where possible.

### 3.3 Modified/Tuning
Stance Auto Magazine (primary), Grassroots Motorsports.

**Pre-launch task, unchanged:** validate every RSS URL is live and returns clean structured data before building ingestion around it.

---

## 4. Core Features

### 4.1 Feed ingestion & clustering (Cloudflare Workers + D1)
- Scheduled RSS polling (Cron Triggers)
- Story clustering — group same story across outlets, show source count rather than duplicate headlines
- Simple heuristic clustering for v1 (shared proper nouns + close publish timestamps)

### 4.2 Image compression (Cloudflare Image Transformations)
- News thumbnails: fetch once from source, resize/convert (e.g. to WebP), cache and serve compressed version
- Requires allowlisting each RSS source's domain in transformation settings (one-time config per source)
- Same product can optionally be applied to TorqueDen's own R2-hosted user images for consistent compression across both content types

### 4.3 Feed blend — News + Builds

- **Segmented toggle at the top of the feed** (News / Builds / Mixed) for v1 — safer than forced interleaving logic, doesn't risk disrupting the existing builds feed people already rely on
- "Mixed" mode: client-side merge of the two content types (avoids building a third aggregation backend layer)
- Interleaving logic for "Mixed" can start simple (recency-sorted merge) and be refined later based on real usage data

### 4.4 Category structure (news side)
Three top-level categories — Racing (sub-filterable by series), Road Cars (sub-filterable by flavor), Modified — matching the structure already designed.

### 4.5 Preferences — reuse existing TorqueDen settings, not a new onboarding flow
- **No new forced onboarding for existing users.** The 3-screen feed-picker wizard (category toggle → series selection → road car flavor) lives in **Settings**, available but not pushed
- New users (post-launch) may see it as a lightweight addition during their existing TorqueDen onboarding, but this is additive, not a redesign of TorqueDen's current signup flow
- Preferences stored per-user — since TorqueDen already has accounts (unlike the original no-account standalone concept), these can sync via Supabase alongside existing user data rather than local-only storage

### 4.6 Launch treatment
- Quiet launch: new feature clearly labeled ("New" badge, one-time announcement card), not a relaunch or rebrand
- No change to TorqueDen's existing name, icon, core positioning

---

## 5. Monetization

- Ads apply to the news feed content, consistent with TorqueDen's existing ad-supported model
- No separate account/paywall for news — it's part of the existing TorqueDen experience for all users (logged in or browsing without an account, per TorqueDen's existing browse-without-account model)

---

## 6. What to Track Post-Launch

Given the "make the app feel more active" motivation — track more than just session length:
- Time spent / interactions on **builds specifically**, not just overall session time, to confirm news is complementing UGC engagement rather than crowding it out
- Which feed mode (News / Builds / Mixed) users actually settle on, to inform whether the segmented-toggle approach should evolve toward smarter blending later

---

## 7. Open Questions

- [ ] WRC feed source — confirm or find alternative
- [ ] German brand / American muscle filtering — confirm usable brand-tagged sub-feeds vs. custom keyword filtering
- [ ] Clustering algorithm — heuristic v1, revisit if too noisy/conservative
- [ ] Poll interval per source
- [ ] "Mixed" feed blend logic — simple recency merge for v1, or worth a smarter weighting from day one?
- [ ] In-app reader vs. link-out only for news stories
- [ ] R2 migration timeline for existing images — parallel workstream, not blocking news feature build
- [ ] Should news preferences sync via Supabase (tied to account) given TorqueDen already has auth, rather than local-only as in the original standalone concept?

---

## 8. Explicitly Out of Scope for This Phase

- Full app relaunch / rebrand / new App Store positioning
- Forced onboarding changes for existing users
- Migrating any part of Supabase Auth or Postgres to Cloudflare
- Smart/ML-based feed blending (start with simple toggle + recency merge)
- Video content aggregation (text/RSS only)

---

*Branding and visual design for how news/build cards look together handled separately. This document covers feature scope and technical architecture only.*
