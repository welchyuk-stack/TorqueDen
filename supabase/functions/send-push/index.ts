// Sends a remote push (FCM HTTP v1) for a newly-created notification row.
//
// Wiring: a Supabase Database Webhook on INSERT to `notifications` POSTs the
// new row here (with an Authorization: Bearer <PUSH_WEBHOOK_AUTH> header). This
// looks up the recipient's device tokens and delivers the push to each, and
// prunes any tokens FCM reports as stale.
//
// Deploy:  supabase functions deploy send-push --no-verify-jwt
// Secrets: supabase secrets set PUSH_WEBHOOK_AUTH=<random> \
//            FCM_SERVICE_ACCOUNT='<the Firebase service-account JSON, one line>'
//          (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY are injected automatically)
// See NOTIFICATIONS-SETUP.md.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const WEBHOOK_AUTH = Deno.env.get('PUSH_WEBHOOK_AUTH') ?? '';
const SA_JSON = Deno.env.get('FCM_SERVICE_ACCOUNT') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data;
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const raw = atob(body);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf.buffer;
}

// Mint a short-lived Google OAuth access token from the service account (RS256
// JWT bearer grant) scoped to FCM.
async function getAccessToken(sa: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claim))}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned)),
  );
  const jwt = `${unsigned}.${b64url(sig)}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`oauth: ${JSON.stringify(json)}`);
  return json.access_token as string;
}

Deno.serve(async (req) => {
  if (!WEBHOOK_AUTH || req.headers.get('Authorization') !== `Bearer ${WEBHOOK_AUTH}`) {
    return new Response('Unauthorized', { status: 401 });
  }

  let record: Record<string, unknown>;
  try {
    const body = await req.json();
    record = (body.record ?? body) as Record<string, unknown>;
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  const userId = record.user_id as string | undefined;
  const title = (record.title as string | undefined) ?? 'TorqueDen';
  const bodyText = (record.body as string | undefined) ?? '';
  if (!userId) return new Response('Missing user_id', { status: 400 });
  if (!SA_JSON) return new Response('FCM not configured', { status: 500 });

  const sa = JSON.parse(SA_JSON) as Record<string, string>;
  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

  const { data: tokens, error } = await supabase
    .from('device_tokens')
    .select('token')
    .eq('user_id', userId);
  if (error) return new Response(`DB: ${error.message}`, { status: 500 });
  if (!tokens || tokens.length === 0) {
    return new Response(JSON.stringify({ ok: true, sent: 0 }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const accessToken = await getAccessToken(sa);
  const endpoint = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
  let sent = 0;
  const stale: string[] = [];
  for (const { token } of tokens as { token: string }[]) {
    const r = await fetch(endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: { token, notification: { title, body: bodyText } },
      }),
    });
    if (r.ok) {
      sent++;
    } else if (r.status === 404 || r.status === 400) {
      stale.push(token); // token unregistered / invalid — prune it
    }
  }
  if (stale.length) {
    await supabase.from('device_tokens').delete().in('token', stale);
  }

  return new Response(JSON.stringify({ ok: true, sent }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
