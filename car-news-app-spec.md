# Car News Aggregator — Technical Scope

*Multi-source car news app. iOS-native. Free, no account, ad-supported. Branding/visual design handled separately — this covers features and architecture only.*

---

## 1. Core Concept

A single app aggregating car news from free RSS sources across three top-level categories — Racing, Road Cars, Modified — with story clustering (grouping the same story across multiple outlets) as the core differentiator against existing single-source or unclustered aggregators in this space.

---

## 2. Content Sources

### 2.1 Racing

| Series | Source(s) | Feed status |
|---|---|---|
| F1 | Motorsport.com (`/rss/f1`), RaceFans, The Race | Confirmed live |
| NASCAR | Motorsport.com (`/rss/nascar-cup`), NASCAR.com official, FanSided | Confirmed live |
| IndyCar | Motorsport.com, The Race (`/category/indycar`), RaceFans | Confirmed live |
| WRC / Rally | Motorsport.com (likely `/rss/wrc` following series pattern — verify) | Needs confirmation |
| GT3 / British GT | GT REPORT (dedicated GT/endurance outlet) | Confirmed live, strong fit |
| Drifting | Formula DRIFT official blog (`news.formulad.com`), DRIFTING.com (covers Formula D + Japan's D1GP) | Confirmed live |

### 2.2 Road Cars

| Category | Source(s) |
|---|---|
| Major publications | Motor1, Car and Driver, Motor Trend, Autoblog, Carscoops, Jalopnik, Autoweek, Hemmings, The Truth About Cars |
| JDM | Drifted.com, Car Throttle (feature/culture content, not pure breaking news) |
| German / American Muscle | No dedicated single-brand outlets found — solve via tag/category filtering within major-publication feeds (most have brand-specific sub-feeds) rather than hunting standalone niche publishers |

### 2.3 Modified / Tuning

- **Stance Auto Magazine** — primary source; RSS pre-organized into Car Mods/Customisers, Car Tuners, JDM/Ford/Modified Clubs, Drift categories
- **Grassroots Motorsports** — build/project-car and track-day angle
- Caution: legacy print-heritage brands (Import Tuner, Super Street, etc.) may be inactive — verify current publishing activity before integrating

**Pre-launch task:** validate every RSS URL is live, check publishing frequency, confirm feed returns clean structured data (title, summary/snippet, thumbnail, link, pubDate) before building ingestion around it.

---

## 3. Core Features

### 3.1 Feed ingestion & clustering

- Scheduled polling of all source RSS feeds (interval TBD based on source publishing frequency — Motor1/Carscoops alone publish ~168 posts/week combined)
- **Story clustering**: group articles covering the same underlying event/story across multiple outlets into a single feed card, showing source count rather than duplicate headlines
- Clustering approach: match on similarity of headline/entities/publish window — start with a simpler heuristic (shared proper nouns + close publish timestamps) for v1; a more sophisticated NLP-based clustering can follow if the simple version proves too noisy or too conservative
- Each cluster retains links to all contributing source articles (tap through to any of them)

### 3.2 Category structure

Three top-level categories, matching the nav from the design mockups:
- **Racing** — sub-filterable by series (F1, NASCAR, IndyCar, WRC, GT3/British GT, Drifting)
- **Road Cars** — sub-filterable by flavor (Major Pubs, JDM, German, American Muscle)
- **Modified** — builds, tuning, drift culture content

### 3.3 Onboarding / feed picker

Three-screen wizard, as designed:
1. Top-level category toggle (Racing / Road Cars / Modified) — all on by default
2. Racing series selection (only shown if Racing is on) — chip multi-select, nothing pre-selected
3. Road car flavor selection (only shown if Road Cars is on) — chip multi-select, optional

- **Skip visible and equally weighted on every screen**, defaults to "everything on" — never blocks entry to the app
- Wizard shown on first launch only; accessible again later via Settings

### 3.4 Preferences & personalization

- All preferences stored **locally on-device** (UserDefaults or local persistence layer) — no account, no server-side user profile
- Post-onboarding **Settings screen** (not part of initial wizard) for deeper control:
  - Mute a specific source
  - Adjust category/series selections made during onboarding
  - (Possible v2) follow a specific team/driver for boosted prominence in feed

### 3.5 Reading experience

- Tap a story card → either in-app reader view (parsed/cleaned article) or direct link-out to source, **respecting copyright**: never reproduce full article text beyond the RSS feed's own summary/snippet field — headline, snippet, thumbnail, source attribution, and a clear link to the original site
- Save/bookmark stories (local storage, no account needed)
- Basic search across ingested content

### 3.6 Notifications (optional, v1 or v2 decision)

- Breaking news push for selected categories/series
- Should respect user's onboarding selections — no notifications for series/categories the user turned off

---

## 4. Monetization

- **Free, no account, ad-supported**
- Ad implementation: standard mobile ad network integration (e.g., Google AdMob or Apple's own ad framework) — placement TBD in design phase, but should not interrupt the reading flow or appear inside in-app article reader views in a way that risks accidental clicks
- No IAP, no subscription tier planned for v1 — revisit only if ad revenue proves insufficient and a premium ad-free tier becomes worth considering later

---

## 5. Technical Architecture

| Layer | Approach |
|---|---|
| Client | iOS native, Swift/SwiftUI |
| Content ingestion | Scheduled RSS/Atom feed parsing (server-side or on-device — see note below) |
| Clustering | Server-side recommended (see note) — heuristic-based for v1 |
| Local storage | On-device persistence for preferences, saved articles, muted sources — no account, no cloud sync needed given no-account model |
| Ads | Third-party ad SDK (AdMob or similar) |
| Push notifications | APNs, gated by user's category/series preferences |

**Key architecture decision to resolve before building:** does RSS ingestion and clustering happen **server-side** (a lightweight backend polls all sources, clusters, and serves a clean API to the app) or **entirely on-device** (each user's app polls all ~20+ feeds directly and clusters locally)?

- **Server-side is strongly recommended** despite breaking the "zero recurring cost" pattern from earlier discussions (menu bar manager, etc.) — this app fundamentally needs a shared backend because:
  - Polling 20+ RSS feeds from every individual user's device is wasteful and slow (redundant requests, battery/data cost for users)
  - Clustering is more effective done once centrally and served to all users, rather than recomputed per-device
  - A simple, low-cost backend (scheduled job + lightweight database + API) is inexpensive to run relative to the value it provides here — this is a legitimate exception to the "avoid recurring costs" preference, not a contradiction of it
- This does reintroduce a small ongoing hosting cost, unlike the CloudKit-based apps discussed earlier — worth being clear-eyed about that tradeoff going in, though at low user volume this should be genuinely cheap (a scheduled serverless function + small database is likely sufficient, not a heavy always-on server)

---

## 6. Open Questions

- [ ] WRC feed source — confirm Motorsport.com WRC-specific endpoint or find alternative
- [ ] German brand / American muscle filtering — confirm which major-pub feeds have usable brand-tagged sub-feeds vs. needing custom keyword filtering
- [ ] Clustering algorithm — start simple (heuristic) or invest in something more robust from day one?
- [ ] Poll interval per source — balance freshness against server/API load
- [ ] In-app reader vs. link-out only — which gives a better experience without crossing into content reproduction risk?
- [ ] Notifications — v1 scope or v2?
- [ ] Ad placement specifics — left to design phase, but frequency/format needs a technical decision (banner vs. native inline vs. interstitial) that affects both UX and backend/SDK integration

---

## 7. Explicitly Out of Scope for v1

- Accounts/sign-in of any kind
- Cross-device sync (no account means no sync target)
- Premium/ad-free tier
- Comment sections or social features
- Video content aggregation (text/RSS only for v1)

---

*Branding, visual identity, and detailed UI design handled separately. This document covers feature scope and technical architecture only.*
