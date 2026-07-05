// RevenueCat webhook → writes the user's membership tier into
// `user_entitlements` (service role, bypassing RLS — clients can never do this).
//
// Flow: RevenueCat calls this on every subscription event. Rather than track
// each event type, we ask RevenueCat's REST API for the subscriber's current
// entitlements and derive the tier from that — so the row always reflects the
// true state (purchase, renewal, cancellation, expiry, billing issue, refund).
//
// The RevenueCat "app user id" is the Supabase auth uid (set via
// Purchases.logIn(uid) in the app), which is also user_entitlements.user_id.
//
// Deploy:  supabase functions deploy revenuecat-webhook --no-verify-jwt
// Secrets: supabase secrets set REVENUECAT_WEBHOOK_AUTH=... REVENUECAT_REST_API_KEY=sk_...
//          (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY are injected automatically)
// Then in RevenueCat → Project → Integrations → Webhooks, point it at this
// function's URL and set the Authorization header to `Bearer <REVENUECAT_WEBHOOK_AUTH>`.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const WEBHOOK_AUTH = Deno.env.get('REVENUECAT_WEBHOOK_AUTH') ?? '';
const RC_API_KEY = Deno.env.get('REVENUECAT_REST_API_KEY') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

// Must match the RevenueCat entitlement identifiers (and the app's IapConfig).
const PARTNER = 'partner';
const PREMIUM = 'premium';

Deno.serve(async (req) => {
  // 1. Authenticate the webhook via the shared secret set in RevenueCat.
  if (!WEBHOOK_AUTH || req.headers.get('Authorization') !== `Bearer ${WEBHOOK_AUTH}`) {
    return new Response('Unauthorized', { status: 401 });
  }

  // 2. Extract the app user id (= Supabase uid) from the event.
  let appUserId: string | undefined;
  try {
    const body = await req.json();
    appUserId = body?.event?.app_user_id;
  } catch {
    return new Response('Bad request', { status: 400 });
  }
  if (!appUserId) return new Response('Missing app_user_id', { status: 400 });

  // Ignore anonymous RevenueCat ids (no logged-in Supabase user to map to).
  if (appUserId.startsWith('$RCAnonymousID:')) {
    return new Response(JSON.stringify({ ok: true, skipped: 'anonymous' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // 3. Ask RevenueCat for the authoritative current entitlements.
  const rc = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`,
    { headers: { Authorization: `Bearer ${RC_API_KEY}` } },
  );
  if (!rc.ok) {
    return new Response(`RevenueCat lookup failed (${rc.status})`, { status: 502 });
  }
  const sub = await rc.json();
  const ents = sub?.subscriber?.entitlements ?? {};
  const now = Date.now();
  const isActive = (id: string): boolean => {
    const e = ents[id];
    if (!e) return false;
    const exp = e.expires_date ? Date.parse(e.expires_date) : null;
    return exp === null || exp > now; // null expiry = non-expiring / lifetime
  };
  const tier = isActive(PARTNER) ? 'partner' : isActive(PREMIUM) ? 'premium' : 'free';

  // 4. Upsert the tier (service role bypasses RLS).
  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);
  const { error } = await supabase
    .from('user_entitlements')
    .upsert(
      { user_id: appUserId, tier, updated_at: new Date().toISOString() },
      { onConflict: 'user_id' },
    );
  if (error) return new Response(`DB error: ${error.message}`, { status: 500 });

  return new Response(JSON.stringify({ ok: true, tier }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
