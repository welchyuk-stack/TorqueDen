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
- [ ] `supabase/migrations/0021_notifications.sql` (inbox — table + triggers)
- [ ] `supabase/migrations/0022_device_tokens.sql` (push — device tokens)

Once 0021 is applied, the **in-app inbox is fully live**. Everything below is
for remote push only.

## 2. Firebase project (push)
- [ ] Create a Firebase project (use the `torquedenapp@gmail.com` Google account).
- [ ] Add an **iOS app** with bundle id `com.torqueden.app`.
- [ ] Download **GoogleService-Info.plist** → add to `ios/Runner/` (in Xcode,
      add to the Runner target).
- [ ] In Apple Developer → create an **APNs Auth Key (.p8)**; upload it to
      Firebase → Project Settings → Cloud Messaging → Apple app configuration.
      *(Requires the Apple Developer Program — pending.)*
- [ ] Generate a **service-account key** (Project Settings → Service accounts →
      Generate new private key) → this JSON is `FCM_SERVICE_ACCOUNT` below.

## 3. iOS capabilities (Xcode)
- [ ] Signing & Capabilities → add **Push Notifications**.
- [ ] Add **Background Modes** → check **Remote notifications**.
- [ ] (APNs entitlement follows automatically from the provisioning profile.)

## 4. Deploy the push edge function
- [ ] `supabase functions deploy send-push --no-verify-jwt`
- [ ] Secrets:
  - `supabase secrets set PUSH_WEBHOOK_AUTH=<a-long-random-string>`
  - `supabase secrets set FCM_SERVICE_ACCOUNT='<service-account JSON on one line>'`
  - (`SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.)

## 5. Wire the DB webhook
- [ ] Supabase dashboard → Database → **Webhooks** → create a webhook on
      **INSERT** to `public.notifications`, HTTP POST to the `send-push`
      function URL, with header `Authorization: Bearer <PUSH_WEBHOOK_AUTH>`.

## 6. Flip it on & test
- [ ] The client already registers the FCM token on login (`PushService`, guarded
      until Firebase is configured) and drops it on logout. No code change needed
      once GoogleService-Info.plist is present.
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
