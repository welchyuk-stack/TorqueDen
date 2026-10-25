# Notifications — setup checklist

Two layers:

- **In-app inbox** (built, Part A) — a `notifications` feed populated by DB
  triggers that respect `notification_prefs`. Works as soon as **migration
  0021** is applied. No Apple/Firebase dependency.
- **Remote push** (scaffolded, Part B) — FCM delivers a push to a user's
  devices whenever a notification row is created. Needs a Firebase project +
  APNs key (Apple Developer account) before it can go live.

```
event (follow/comment/like/thread/reply)
  └─ DB trigger → insert notifications row (respects notification_prefs)
       ├─ in-app: client reads it (bell + inbox)
       └─ push:   DB webhook on INSERT → send-push edge function
                    └─ look up device_tokens → FCM HTTP v1 → user's devices
```

## 1. Apply the migrations
Via the Supabase Management API (this project isn't CLI-linked — see the
supabase memory) or the dashboard SQL editor:
- [x] `supabase/migrations/0021_notifications.sql` (inbox — table + triggers) — APPLIED
- [x] `supabase/migrations/0022_device_tokens.sql` (push — device tokens) — APPLIED

In-app inbox is live. Everything below is for remote push only.

## 2. Firebase project (push) — **YOUR ACTION**
- [ ] Create a Firebase project at https://console.firebase.google.com
      (use the `torquedenapp@gmail.com` Google account).
- [ ] Add an **iOS app** with bundle id `com.torqueden.app`.
- [ ] Download **GoogleService-Info.plist** → add to `ios/TorqueDen/` in Xcode
      (drag into the Runner target, copy items if needed).
- [ ] In Apple Developer → Keys → create an **APNs Auth Key (.p8)**;
      upload it to Firebase → Project Settings → Cloud Messaging →
      Apple app configuration.
- [ ] Generate a **service-account key** (Firebase Project Settings →
      Service accounts → Generate new private key) → this JSON is
      `FCM_SERVICE_ACCOUNT` below.

## 3. iOS capabilities (Xcode) — **YOUR ACTION**
- [ ] Open `ios/TorqueDen.xcworkspace` → Runner target → Signing & Capabilities.
- [ ] Add **Push Notifications** capability.
- [ ] Add **Background Modes** capability → check **Remote notifications**.

## 4. Deploy the push edge function — run these commands
```bash
supabase functions deploy send-push --no-verify-jwt --project-ref <your-project-ref>
supabase secrets set PUSH_WEBHOOK_AUTH=<a-long-random-string> --project-ref <your-project-ref>
supabase secrets set FCM_SERVICE_ACCOUNT='<service-account JSON, all on one line>' --project-ref <your-project-ref>
```

## 5. Wire the DB webhook — Supabase dashboard
- [ ] Supabase dashboard → Database → **Webhooks** → New webhook.
  - Table: `public.notifications`, Event: `INSERT`
  - URL: `https://<project-ref>.supabase.co/functions/v1/send-push`
  - Header: `Authorization: Bearer <PUSH_WEBHOOK_AUTH>`

## 6. Flip it on & test
- [x] Client registers FCM token on login (`PushService`) — no code change needed.
- [x] Client drops token on logout — done.
- [ ] Add `GoogleService-Info.plist` to Xcode (step 2 above).
- [ ] Build + run on a **real device** (push doesn't work in the iOS Simulator).
- [ ] Trigger a follow event → confirm push arrives on device.
- [ ] Confirm toggling the matching pref off suppresses the push.
- [ ] Sandbox-test on a real device (push doesn't work on the iOS Simulator):
      trigger an event (e.g. follow the test account) → confirm an inbox row
      appears AND a push arrives → confirm toggling the matching pref off
      suppresses both.

## Notes
- The inbox and push share the same `notification_prefs` gating (the triggers
  create rows only when the pref is on; push only fires for rows that exist).
- Deep-linking from a tapped notification to the exact post/thread is a
  follow-up (currently tapping just marks it read).
- Legacy FCM server keys are dead — this uses **FCM HTTP v1** with a service
  account (the edge function mints an OAuth token itself).
