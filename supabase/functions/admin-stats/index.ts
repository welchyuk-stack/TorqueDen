// Private admin dashboard API — powers the "for me only" stats page at
// torquedenapp.com/admin/. Everything here runs with the service role key
// (bypasses RLS), so access is gated by a single shared secret instead of a
// user login: the caller must send `x-admin-key: <ADMIN_DASHBOARD_KEY>`.
// The key itself is never committed to the repo or shipped in the HTML —
// you type it once into the dashboard page and it's kept in your browser's
// localStorage from then on.
//
// GET  /admin-stats            -> aggregate counts + recent signups + open reports
// POST /admin-stats  {action:"resolve_report", reportId, status}
//                                -> mark a report "resolved" or "dismissed"
//
// Deploy:  supabase functions deploy admin-stats --no-verify-jwt
// Secrets: supabase secrets set ADMIN_DASHBOARD_KEY=<pick a long random string>
//          (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY are injected automatically)

import { createClient } from 'jsr:@supabase/supabase-js@2';

const ADMIN_KEY = Deno.env.get('ADMIN_DASHBOARD_KEY') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': 'https://torquedenapp.com',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-admin-key',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS_HEADERS });

  // 1. Gate on the shared admin key. Constant-time-ish check isn't critical
  // here (single operator, low-value timing attack), but length check first
  // avoids the common empty-secret misconfiguration footgun.
  const key = req.headers.get('x-admin-key') ?? '';
  if (!ADMIN_KEY || key !== ADMIN_KEY) {
    return json({ error: 'Unauthorized' }, 401);
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

  // --- Write actions -------------------------------------------------------
  if (req.method === 'POST') {
    let body: any;
    try {
      body = await req.json();
    } catch {
      return json({ error: 'Bad request' }, 400);
    }

    if (body?.action === 'resolve_report') {
      const { reportId, status } = body;
      if (!reportId || !['resolved', 'dismissed'].includes(status)) {
        return json({ error: 'Invalid resolve_report payload' }, 400);
      }
      const { error } = await supabase
        .from('reports')
        .update({ status })
        .eq('id', reportId);
      if (error) return json({ error: error.message }, 500);
      return json({ ok: true });
    }

    return json({ error: 'Unknown action' }, 400);
  }

  // --- Read stats -----------------------------------------------------------
  const since7d = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const since30d = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

  const count = async (table: string, filter?: (q: any) => any) => {
    let q = supabase.from(table).select('*', { count: 'exact', head: true });
    if (filter) q = filter(q);
    const { count: c, error } = await q;
    if (error) throw new Error(`${table}: ${error.message}`);
    return c ?? 0;
  };

  try {
    const [
      totalUsers,
      newUsers7d,
      newUsers30d,
      totalClubs,
      publicClubs,
      totalCars,
      totalPosts,
      totalComments,
      totalReactions,
      premiumSubs,
      partnerSubs,
      openReports,
    ] = await Promise.all([
      count('profiles'),
      count('profiles', (q) => q.gte('created_at', since7d)),
      count('profiles', (q) => q.gte('created_at', since30d)),
      count('clubs'),
      count('clubs', (q) => q.eq('is_public', true)),
      count('cars'),
      count('build_entries'),
      count('post_comments'),
      count('post_likes'),
      count('user_entitlements', (q) => q.eq('tier', 'premium')),
      count('user_entitlements', (q) => q.eq('tier', 'partner')),
      count('reports', (q) => q.eq('status', 'open')),
    ]);

    // Recent open reports, with reporter username for context.
    const { data: reportRows, error: reportErr } = await supabase
      .from('reports')
      .select('id, target_type, target_id, reason, note, status, created_at, reporter_id')
      .eq('status', 'open')
      .order('created_at', { ascending: false })
      .limit(25);
    if (reportErr) throw new Error(`reports detail: ${reportErr.message}`);

    const reporterIds = [...new Set((reportRows ?? []).map((r) => r.reporter_id))];
    let reporterNames: Record<string, string> = {};
    if (reporterIds.length) {
      const { data: profileRows } = await supabase
        .from('profiles')
        .select('id, username')
        .in('id', reporterIds);
      reporterNames = Object.fromEntries((profileRows ?? []).map((p) => [p.id, p.username]));
    }

    const reports = (reportRows ?? []).map((r) => ({
      ...r,
      reporter_username: reporterNames[r.reporter_id] ?? 'unknown',
    }));

    // Recent signups for a lightweight growth list.
    const { data: recentSignups } = await supabase
      .from('profiles')
      .select('username, created_at')
      .order('created_at', { ascending: false })
      .limit(10);

    return json({
      generated_at: new Date().toISOString(),
      users: { total: totalUsers, new_7d: newUsers7d, new_30d: newUsers30d },
      clubs: { total: totalClubs, public: publicClubs, private: totalClubs - publicClubs },
      content: { cars: totalCars, posts: totalPosts, comments: totalComments, reactions: totalReactions },
      subscribers: { premium: premiumSubs, partner: partnerSubs },
      moderation: { open_reports: openReports },
      reports,
      recent_signups: recentSignups ?? [],
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
