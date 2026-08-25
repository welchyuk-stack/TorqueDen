// challenge-tick — called by Supabase Cron twice on Friday.
//
// Schedule A (Fri 17:00 UTC):  send "winner" push, insert badge, mark announced
// Schedule B (Fri 18:00 UTC):  send "new challenge" push
//
// Cron expressions (set in Supabase Dashboard → Edge Functions → Schedules):
//   Winner:   0 17 * * 5
//   Announce: 0 18 * * 5
//
// Invoke manually for testing:
//   supabase functions invoke challenge-tick --body '{"mode":"announce"}' --no-verify-jwt
//   supabase functions invoke challenge-tick --body '{"mode":"winner"}' --no-verify-jwt
//
// Deploy:
//   supabase functions deploy challenge-tick --no-verify-jwt
// Secrets:
//   supabase secrets set CHALLENGE_TICK_AUTH=<random>
// The cron schedules must send `Authorization: Bearer <CHALLENGE_TICK_AUTH>`.
//
// The shared secret is required because this runs with --no-verify-jwt: without
// it the endpoint is open to anyone who knows the URL, and `mode` is read from
// the request body, so the Friday-only window in detectMode() is bypassed by
// simply passing {"mode":"winner"}. An unauthenticated caller could close the
// challenge early, award the badge, and re-trigger the push fan-out to every
// device token on demand. Same pattern as send-push / admin-stats.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const TICK_AUTH = Deno.env.get('CHALLENGE_TICK_AUTH') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const APNS_KEY_ID = Deno.env.get('APNS_KEY_ID') ?? '';
const APNS_TEAM_ID = Deno.env.get('APNS_TEAM_ID') ?? '';
const APNS_BUNDLE_ID = Deno.env.get('APNS_BUNDLE_ID') ?? 'com.torqueden.app';
const APNS_PRIVATE_KEY = Deno.env.get('APNS_PRIVATE_KEY') ?? '';

const db = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
const anonDb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

Deno.serve(async (req) => {
  if (!TICK_AUTH || req.headers.get('Authorization') !== `Bearer ${TICK_AUTH}`) {
    return new Response('Unauthorized', { status: 401 });
  }

  const body = req.method === 'POST' ? await req.json().catch(() => ({})) : {};
  const mode: string = body.mode ?? detectMode();

  if (mode === 'announce') {
    return await handleAnnounce();
  } else if (mode === 'winner') {
    return await handleWinner();
  }
  return json({ ok: false, message: 'Unknown mode. Pass mode="announce" or mode="winner".' }, 400);
});

// ── Mode detection ────────────────────────────────────────────────────────────

function detectMode(): string {
  const h = new Date().getUTCHours();
  const d = new Date().getUTCDay(); // 0=Sun, 1=Mon
  if (d === 5 && h >= 17 && h < 18) return 'winner';   // Fri ~17:00 UTC
  if (d === 5 && h >= 18 && h < 19) return 'announce'; // Fri ~18:00 UTC
  return 'none';
}

// ── Announce new challenge ────────────────────────────────────────────────────

async function handleAnnounce() {
  const now = new Date().toISOString();
  const { data: challenges } = await anonDb
    .from('challenges')
    .select('*')
    .lte('starts_at', now)
    .gte('ends_at', now)
    .order('starts_at', { ascending: false })
    .limit(1);

  if (!challenges?.length) {
    return json({ ok: true, message: 'No active challenge to announce.' });
  }
  const c = challenges[0];
  const tokens = await getTokens('challenge_updates');
  const sent = await sendPushToAll(tokens, {
    title: `${c.emoji} The Shot is live`,
    body: c.title,
  });
  return json({ ok: true, sent, challenge: c.title });
}

// ── Announce winner ───────────────────────────────────────────────────────────

async function handleWinner() {
  const now = new Date().toISOString();

  // Find the most recently ended challenge not yet announced.
  const { data: challenges } = await db
    .from('challenges')
    .select('*')
    .lt('ends_at', now)
    .eq('winner_announced', false)
    .order('ends_at', { ascending: false })
    .limit(1);

  if (!challenges?.length) {
    return json({ ok: true, message: 'No unannounced challenge found.' });
  }
  const c = challenges[0];

  // Auto-pick winner by vote count from challenge_votes.
  const { data: votes } = await db
    .from('challenge_votes')
    .select('entry_id')
    .eq('challenge_id', c.id);

  if (!votes?.length) {
    // No votes cast — mark announced with no winner.
    await db.from('challenges').update({ winner_announced: true }).eq('id', c.id);
    return json({ ok: true, message: 'No votes cast — no winner this week.', challenge: c.title });
  }

  // Tally votes.
  const tally: Record<string, number> = {};
  for (const v of votes) {
    tally[v.entry_id] = (tally[v.entry_id] ?? 0) + 1;
  }
  const winnerEntryId = Object.entries(tally).sort((a, b) => b[1] - a[1])[0][0];

  // Fetch winning entry's car.
  const { data: entry } = await db
    .from('build_entries')
    .select('car:cars(id, nickname, make, model)')
    .eq('id', winnerEntryId)
    .single();

  const car = (entry as any)?.car;
  const carName = car?.nickname || `${car?.make ?? ''} ${car?.model ?? ''}`.trim() || 'a build';

  // Write winner back to challenges row.
  await db.from('challenges')
    .update({ winner_entry_id: winnerEntryId, winner_announced: true })
    .eq('id', c.id);

  // Insert badge.
  await db.from('car_badges').upsert(
    { car_id: car.id, challenge_id: c.id },
    { onConflict: 'car_id,challenge_id', ignoreDuplicates: true },
  );

  // Push.
  const tokens = await getTokens('challenge_updates');
  const sent = await sendPushToAll(tokens, {
    title: `🏆 ${c.title} The Shot winner`,
    body: carName,
  });

  return json({ ok: true, sent, challenge: c.title, winner: carName, votes: tally[winnerEntryId] });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

async function getTokens(pref: string): Promise<string[]> {
  const { data } = await db
    .from('device_tokens')
    .select('token, notification_prefs!inner(challenge_updates)')
    .eq(`notification_prefs.${pref}`, true);
  return (data ?? []).map((r: any) => r.token as string);
}

async function sendPushToAll(
  tokens: string[],
  payload: { title: string; body: string },
): Promise<number> {
  if (!tokens.length || !APNS_KEY_ID) return 0;
  // Delegate to the existing send-push function rather than re-implementing APNs.
  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/send-push`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      },
      body: JSON.stringify({ tokens, ...payload }),
    });
    const data = await res.json();
    return (data as any).sent ?? 0;
  } catch {
    return 0;
  }
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
