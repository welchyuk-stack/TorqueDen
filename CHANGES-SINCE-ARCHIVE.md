# Changes since last archive

Reset this file each time you build and archive in Xcode.

---

## Session 2026-07-20

### Meets card — ember orange colour filter
- `lib/screens/community_screen.dart` — tuned `_MeetsIllustration` colour-filter matrix to ember orange (R×0.88, G×0.32, B×0.17); separate light/dark values.

### Meet detail — address + map fixes
- `lib/screens/meet_detail_screen.dart` — map section now always shown (falls back to UK overview zoom-5 when no coords); pin only rendered when coords available.
- `lib/screens/create_meet_screen.dart` — auto-geocodes address on load when editing a meet that has address text but no lat/lng (`addPostFrameCallback` → `_geocodeAddress()`).

### Global platform ban
- `supabase/migrations/0031_platform_bans.sql` — adds `is_banned boolean` column to profiles + unique index on `lower(username)`. **Applied to prod.**
- `lib/screens/admin_screen.dart` — new Platform Admin screen: search users by username/display name, view strike count + ban status, ban/unban with confirmation dialog.
- `lib/screens/account_screen.dart` — Platform Admin entry point gated behind admin UID (`807e6e7c…`).

### Forum duplicate name check
- `lib/screens/create_club_screen.dart` — blocks creation if a forum with the same name already exists (case-insensitive `ilike` check + snack-bar error).

### Clubs → Forums rename (UI strings only)
- `lib/screens/clubs_screen.dart`, `club_detail_screen.dart`, `club_manage_screen.dart`, `create_club_screen.dart`, `thread_detail_screen.dart`, `account_screen.dart`, `membership_screen.dart`, `notifications_screen.dart`, `notifications_list_screen.dart`, `about_screen.dart`, `utils/post_error.dart` — all user-visible "Club/Clubs" strings replaced with "Forum/Forums". Class names, file names, and DB table names unchanged.

### Soft duplicate meet warning
- `lib/screens/create_meet_screen.dart` — warns before saving if a meet with the same title exists in the same calendar week; user can dismiss and create anyway.

### Change-email crash fix
- `lib/screens/account_screen.dart` — `_InputDialog` now owns its own `TextEditingController` (via `initialValue` + `initState`/`dispose`); removed external controller that was disposed during exit animation.

### Delete own comments on posts
- `lib/widgets/comments_sheet.dart` — own comments show a red "Delete" link below the text; tapping confirms then hard-deletes the row and refreshes. Other users' comments unchanged (moderation long-press only).

### Delete own posts from feed
- `lib/screens/feed_screen.dart` — `⋮` button on own posts now shows a "Delete post?" confirm dialog instead of the moderation sheet; deletes `build_entries` row and refreshes feed.

### Guest / browse-without-account mode
- `lib/services/guest_mode.dart` — new singleton; `GuestMode.enable()` / `GuestMode.clear()` / `GuestMode.isGuest`.
- `lib/screens/auth/auth_screen.dart` — "Browse as guest" text button at the bottom of the login screen.
- `lib/screens/auth/auth_gate.dart` — shows `MainShell` when guest mode is active (instead of `AuthScreen`); clears guest mode on sign-out.
- `lib/main_shell.dart` — Feed / Garage / DMs tabs replaced with `_GuestPlaceholder` sign-up prompt when guest; "+" button shows nudge sheet.
- `lib/widgets/guest_nudge_sheet.dart` — reusable bottom sheet: "Join TorqueDen" with Create account + Log in buttons; clearing guest mode triggers `AuthGate` to rebuild into `AuthScreen`.
- `lib/widgets/like_button.dart` — shows guest nudge instead of reaction picker.
- `lib/widgets/follow_button.dart` — shows guest nudge instead of toggling follow.
- `lib/widgets/comments_sheet.dart` — shows guest nudge when guest tries to post a comment.
- `lib/screens/meet_detail_screen.dart` — shows guest nudge on RSVP.
- `lib/screens/meets_screen.dart` — shows guest nudge on "Create meet".
- `lib/screens/club_detail_screen.dart` — shows guest nudge on "Join forum".

### Image compression before upload
- `lib/utils/image_compress.dart` — new utility: skips files already under 200 KB; otherwise resizes to max 1600px on the longest edge and re-encodes as JPEG at quality 82, running in a background isolate via `compute()`.
- Applied in `create_post_screen.dart`, `add_car_screen.dart`, `create_club_screen.dart`, `widgets/car/build_tab.dart`.

### Banned-user RLS enforcement
- `supabase/migrations/0032_ban_rls_enforcement.sql` — new migration: drops and recreates INSERT policies on `build_entries`, `post_comments`, `club_threads`, `club_replies`, `car_meets`, `meet_rsvps` to include `is_banned = false` check. **Needs applying in Supabase.**

### Report flow for meets
- `lib/screens/meet_detail_screen.dart` — non-owners now see a `⋮` button in the app bar that opens the moderation sheet with `targetType: 'meet'`.

### Edit post caption
- `lib/screens/feed_screen.dart` — owner's `⋮` button now shows an action sheet (Edit caption / Delete post) instead of going straight to delete.
- `lib/widgets/car/posts_tab.dart` — long-press on own post in the profile grid now shows an action sheet (Edit caption / Delete post). Edit fetches current title from DB and opens an edit dialog.

### Misc cleanup
- `lib/screens/create_club_screen.dart` — "Create club" button label and validator message updated to "forum".
