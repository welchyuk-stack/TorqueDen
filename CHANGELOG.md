# TorqueDen Changelog

## 1.2.0
### Feed & Discovery
- Feed is now open to everyone — no account needed to browse builds
- Full-width images in the feed (no rounding, 4:3 ratio)
- Text-only posts styled with an ember left-border accent card
- Feed resets to your personalised timeline the moment you sign in
- Search bar sits closer to the app bar, giving tag pills more room to breathe
- Pull-to-refresh on the Messages tab

### The Shot (weekly challenge)
- Showdown renamed to **The Shot** throughout the app
- Your entry now shows as a pinned rank banner above the leaderboard
- Upvote button moved to the bottom-right of each entry tile; car label made larger
- Entry list now surfaces errors clearly instead of silently failing

### Navigation & UI
- App now opens directly to the feed — no login wall
- Nav bar hides on scroll (Instagram-style) and reappears when you scroll back or stop
- Nav and bell icons updated to cream colour
- Settings moved permanently into the nav bar; cog removed from all inner screens
- Discover filter chips and "Near Me" / "The Shot" buttons resized for consistency

## 1.1.1
- Images in the feed now load via Supabase image transforms (800px / 75% quality), reducing data usage by ~93% for feed browsing
- Deleting a post now removes the associated image files from storage, preventing orphaned files accumulating
- Client-side image compression before upload

## 1.0.0
- Initial release
