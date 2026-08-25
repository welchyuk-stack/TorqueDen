# TorqueDen — Direct Messages, Events/Meetups & Moderation Review

Scoped against the actual current schema (`supabase/schema.sql` + `migrations/0001`–`0024`) and app code (`lib/`), not just the feature list — so what's marked "already have" below is genuinely already built, not assumed.

---

## 1. Direct Messages (DMs)

### What already exists that this reuses
The notification pipeline is the one piece of infrastructure that makes this much smaller than it sounds. There's already a `notifications` table with a `push_notification()` helper, a trigger pattern (insert → notification row → DB webhook → `send-push` Edge Function → FCM), a `device_tokens` table keyed per-device, and a `notification_prefs` table for per-type opt-outs. Every existing notification type (`new_follower`, `post_comment`, `post_like`, `club_new_thread`, `thread_reply`, `comment_reply`) follows the same shape. DMs just need to be type #7 in that same system — no new push infrastructure required.

### New schema needed
- `dm_threads` — id, participant pair (or a `dm_participants` join table if group DMs are ever wanted, but 1:1 only for v1 keeps this simple), `created_at`, `last_message_at` (for sorting the inbox).
- `dm_messages` — id, thread_id, sender_id, body, created_at, `read_at` (nullable — powers unread badges).
- A uniqueness constraint on the participant pair so re-opening a DM with the same person reuses the thread instead of creating duplicates.

### RLS shape (matches the existing pattern exactly)
Same style as `club_members`/`club_threads`: a user can only select a thread they're a participant in, and can only insert a message into a thread they're a participant in. Trivial to write given the existing policies as a template.

### Moderation hooks (important — see §3)
- Reuse `blocks` as-is: if either party has blocked the other, the thread can't be created (check in the insert policy) and existing threads should stop delivering new messages both ways — the existing `Moderation.blockedIds` client-side set already does the "hide their content" half of this, it just needs to also gate DM sends.
- Reuse `showModerationSheet` / `reports` for a "Report this conversation" action on a DM thread — `target_type: 'dm_thread'` slots straight into the existing reports table with zero schema change.
- New for this feature: a **message rate limit** (something `club_mutes`/slow-mode doesn't currently need to think about for open feed content but DMs are a classic spam/harassment vector — a simple "N messages per minute to a non-mutual" check is worth having from day one, not bolted on after an abuse report).

### Push notification
New `push_notification()` call: `p_type := 'new_message'`, `p_pref := 'direct_messages'` (new column on `notification_prefs`), title `"{sender} sent you a message"`, body = truncated message text. Everything downstream (device token lookup, FCM send) is unchanged.

### UI
New `dm_inbox_screen.dart` (list of threads, unread bolding) and `dm_thread_screen.dart` (message list + composer) — same visual language as `thread_detail_screen.dart` already gives a close template to build from.

### Rough size
Given the reused push/report/block plumbing, this is closer to a 1.5–2.5 week build than a from-scratch messaging feature — the hard infrastructure part is already done.

---

## 2. Events / Meetups

### Why this is the bigger opportunity
This isn't a "nice to have" bolt-on — it's the entire product for several direct competitors (AutoLNK, Meetz, Drivurs, CarMeets, AutoMeet). TorqueDen's Discover tab currently does "near me" for builds and people (via `cars.latitude/longitude` with fuzzing) but has no concept of an organized event at all — no calendar, no RSVP, nothing to plan a cruise night through the app itself.

### How competitors actually curate their event databases (researched, not assumed)
It's overwhelmingly **user-submitted, not editorially curated**. Any user creates an event and it's live near-instantly (this is explicitly how Oklahoma Car Meets and CarMeets.app work). What keeps that from becoming spam is layered *after-the-fact* trust & safety, not upfront gatekeeping:
- Automated abuse/rate-limit detection on the creation pattern itself (repeated rapid posting = bot signal).
- A report-this-event / report-this-organizer flow, reviewed by moderators (Meetup.com's model is the clearest reference).
- Visibility tiers — public / club-only / invite-only (Drivurs) — so a private cruise doesn't have to be discoverable by strangers.
- An optional "verified organizer" badge for business/paid accounts specifically (CarShowsAU does this via Stripe identity verification), left for later rather than a v1 requirement.

**This maps almost exactly onto TorqueDen's existing club moderation model** — open creation, a `reports` table, mod tooling (bans/mutes/mod log). Events can reuse that philosophy directly rather than needing a new one invented from scratch.

### New schema needed
- `events` — id, creator_id, club_id (nullable — an event can be club-hosted or standalone), title, description, location_name, latitude/longitude, starts_at, ends_at (nullable), is_public (mirrors `clubs.is_public`), cover_image_url, created_at.
- `event_rsvps` — id, event_id, user_id, status (`going`/`interested`), created_at — powers headcounts and "who's going" lists.
- Optionally, `event_comments` reusing the same shape as `post_comments` rather than inventing a new comment table.

### Moderation hooks
- `reports.target_type` gets a new value: `'event'`. Zero schema change to the reports table itself.
- A lightweight version of `can_post_now()` (the existing slow-mode function) applied to event *creation* rather than posting — e.g. no more than N events per user per day — is the direct equivalent of the "automated abuse detection" competitors use, and it's a two-line reuse of a pattern that already exists.
- Club-hosted events (`club_id` set) inherit that club's existing mod team automatically — an event inside a locked/archived club shouldn't be creatable, same check already used for threads.
- The admin dashboard's existing open-reports queue (`admin-stats` Edge Function) just needs `'event'` added to the target types it already lists reporter/reason/status for — no new admin surface needed.

### Discovery
This is the one part that's genuinely new UI, not reuse: an events list/map view, filterable by distance/date, probably living as a new tab on the existing Discover screen rather than a whole new nav item — keeps it from fragmenting the "find people near me" concept that's already there.

### Rough size
Bigger than DMs — new list/map UI, RSVP flow, and (if wanted later) the "group drive with live location share" feature several competitors have is its own follow-on phase, not a v1 requirement. A solid v1 (create/discover/RSVP/report) is realistically a 3–5 week build.

---

## 3. Moderation systems — current-state review

Went through every moderation-related table, RLS policy, and screen to see what's actually there today rather than what the feature list implies.

**What's genuinely solid:**
Club-level moderation is mature — bans, timed mutes, a substring-based blocked-word filter enforced at the database trigger level (not just client-side), slow mode, an audit log (`club_mod_log`) recording every mod action with actor/target/detail, and role-based permission checks (`is_club_mod()`) used consistently across every relevant RLS policy. This is well above what a lot of early-stage community apps ship with.

User-level moderation is also solid for what it covers: `blocks` is fully private to the blocker, enforced via RLS, and consistently checked client-side (`Moderation.blockedIds`) to filter out a blocked user's content. The report flow (`showModerationSheet` → four-reason picklist → optional note → `reports` insert) is clean and already meets the App Store's requirement that user-generated-content apps have both a block and a report path.

**The real gap: reports go into a queue, but nothing closes the loop on the content itself.** Resolving a report in the admin dashboard (`admin-stats`'s `resolve_report` action) only flips the report's `status` to resolved/dismissed — it doesn't delete, hide, or otherwise act on the actual post/thread/comment that was reported. Right now, acting on a report means going into Supabase directly to remove the offending row by hand. That's fine at current scale; it will not be fine once report volume is more than "the founder checks it a couple of times a day." Worth adding before DMs and Events both add new report target types on top of the existing ones: a "take action" set of buttons on each report row in the admin dashboard — delete the target content, and optionally auto-ban/mute the author — that write to the *same* content tables the app already uses, rather than needing raw database access.

**Two smaller gaps worth naming:**
- The blocked-word filter only exists for club threads/replies (`check_thread_words`/`check_reply_words` triggers) — it doesn't apply to the main feed's `post_comments`, and won't automatically apply to DMs or event descriptions unless explicitly added. Worth deciding whether that's a global filter or stays club-scoped as clubs add their own custom words list.
- There's no rate limiting on **report filing itself** — nothing stops one user from spamming reports against another as a harassment vector. Low risk today at this user count, but worth a note for later (e.g., cap reports-per-user-per-hour).

**For DMs and Events specifically**, the moderation additions needed are small precisely *because* the existing model (reports + blocks + reusable checks like `is_club_mod`/`can_post_now`) was built in a genuinely reusable shape — new content types slot into `reports.target_type` and new abuse-pattern checks are two-line variations of `can_post_now()`, not new systems.

---

## 4. Suggested build order

1. **Admin "take action" on reports** first — small, and both new features below will only add more report volume on top of a queue that currently can't act on itself.
2. **DMs** — smaller build, reuses the most existing infrastructure (push, blocks, reports), delivers a feature every social app is expected to have.
3. **Events/Meetups v1** (create, discover, RSVP, report) — bigger build, but the one most likely to actually differentiate TorqueDen from being "Instagram for cars" into "the app that gets you to an actual meet."
