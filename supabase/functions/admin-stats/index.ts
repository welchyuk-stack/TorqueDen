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
// Free-tier hard limits — used to compute headroom in the admin panel.
const FREE_LIMITS = {
  db_size_bytes:        500 * 1024 * 1024,        // 500 MB
  storage_size_bytes:   1   * 1024 * 1024 * 1024, // 1 GB
};

// build_entries has no user_id — author is via cars.owner_id.
// All other content types have a direct user_id or creator_id column.
async function resolveAuthor(supabase: any, targetType: string, targetId: string): Promise<string | null> {
  if (targetType === 'post') {
    const { data } = await supabase
      .from('build_entries')
      .select('cars(owner_id)')
      .eq('id', targetId)
      .single();
    return (data?.cars as any)?.owner_id ?? null;
  }
  const map: Record<string, { table: string; col: string }> = {
    comment: { table: 'post_comments', col: 'user_id' },
    thread:  { table: 'club_threads',  col: 'user_id' },
    reply:   { table: 'club_replies',  col: 'user_id' },
    club:    { table: 'clubs',         col: 'creator_id' },
  };
  const entry = map[targetType];
  if (!entry) return null;
  const { data } = await supabase.from(entry.table).select(entry.col).eq('id', targetId).single();
  return data?.[entry.col] ?? null;
}

// Allow both http:// and https:// on the domain (the site may still be on
// http while the GitHub Pages cert finishes issuing), plus the raw GitHub
// Pages URL as a fallback, and localhost for testing this file directly.
const ALLOWED_ORIGINS = [
  'https://torquedenapp.com',
  'http://torquedenapp.com',
  'https://www.torquedenapp.com',
  'http://www.torquedenapp.com',
  'https://welchyuk-stack.github.io',
];

function corsHeaders(origin: string | null) {
  const allowOrigin =
    origin && (ALLOWED_ORIGINS.includes(origin) || origin.startsWith('http://localhost'))
      ? origin
      : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-admin-key',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    Vary: 'Origin',
  };
}

function json(body: unknown, status = 200, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get('origin'));
  const j = (body: unknown, status = 200) => json(body, status, headers);

  if (req.method === 'OPTIONS') return new Response(null, { headers });

  // 1. Gate on the shared admin key. Constant-time-ish check isn't critical
  // here (single operator, low-value timing attack), but length check first
  // avoids the common empty-secret misconfiguration footgun.
  const key = req.headers.get('x-admin-key') ?? '';
  if (!ADMIN_KEY || key !== ADMIN_KEY) {
    return j({ error: 'Unauthorized' }, 401);
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

  // --- Write actions -------------------------------------------------------
  if (req.method === 'POST') {
    let body: any;
    try {
      body = await req.json();
    } catch {
      return j({ error: 'Bad request' }, 400);
    }

    if (body?.action === 'resolve_report') {
      const { reportId, status } = body;
      if (!reportId || !['resolved', 'dismissed'].includes(status)) {
        return j({ error: 'Invalid resolve_report payload' }, 400);
      }
      const { error } = await supabase
        .from('reports')
        .update({ status })
        .eq('id', reportId);
      if (error) return j({ error: error.message }, 500);
      return j({ ok: true });
    }

    // Issue a formal warning: increment strike_count on the reported user's profile,
    // send them a warning notification, and close the report as 'resolved'.
    if (body?.action === 'warn') {
      const { reportId } = body;
      if (!reportId) return j({ error: 'reportId required' }, 400);

      const { data: report, error: rErr } = await supabase
        .from('reports')
        .select('target_type, target_id, status')
        .eq('id', reportId)
        .single();
      if (rErr || !report) return j({ error: 'Report not found' }, 404);
      if (report.status !== 'open') return j({ error: 'Report already actioned' }, 409);

      // Resolve the target to a user id.
      let userId: string | null = null;
      if (report.target_type === 'user') {
        userId = report.target_id;
      } else {
        userId = await resolveAuthor(supabase, report.target_type, report.target_id);
      }
      if (!userId) return j({ error: 'Could not resolve user from report' }, 400);

      // Increment strike count.
      const { data: profile } = await supabase.from('profiles').select('strike_count').eq('id', userId).single();
      const newCount = ((profile?.strike_count ?? 0) as number) + 1;
      await supabase.from('profiles').update({ strike_count: newCount }).eq('id', userId);

      // Send a warning notification to the user.
      const isSecond = newCount >= 2;
      await supabase.from('notifications').insert({
        user_id: userId,
        type: 'announcement',
        actor_id: null,
        title: isSecond ? 'Final warning — your account is at risk' : 'Community guidelines warning',
        body: isSecond
          ? 'Your content has been removed for a second time. Any further violations will result in a permanent ban.'
          : 'Some of your content was removed for breaching our Community Guidelines. Please review the guidelines in Settings.',
        read: false,
      });

      // Mark report resolved.
      await supabase.from('reports').update({ status: 'resolved' }).eq('id', reportId);

      return j({ ok: true, strike: newCount });
    }

    // Delete the reported content. Optionally also deletes the author's account.
    if (body?.action === 'delete_content' || body?.action === 'delete_and_ban') {
      const { reportId, banUser } = body;
      if (!reportId) return j({ error: 'reportId required' }, 400);

      // Fetch the report so we know what to delete.
      const { data: report, error: rErr } = await supabase
        .from('reports')
        .select('target_type, target_id, status')
        .eq('id', reportId)
        .single();
      if (rErr || !report) return j({ error: 'Report not found' }, 404);
      if (report.status !== 'open') return j({ error: 'Report already actioned' }, 409);

      const { target_type, target_id } = report;

      let authorId: string | null = null;

      if (target_type === 'user') {
        authorId = target_id;
      } else {
        const contentTableMap: Record<string, string> = {
          post: 'build_entries', comment: 'post_comments',
          thread: 'club_threads', reply: 'club_replies', club: 'clubs',
        };
        const table = contentTableMap[target_type];
        if (!table) return j({ error: `Unknown target_type: ${target_type}` }, 400);

        // Resolve author before deleting.
        authorId = await resolveAuthor(supabase, target_type, target_id);

        // Delete the content.
        const { error: delErr } = await supabase.from(table).delete().eq('id', target_id);
        if (delErr) return j({ error: `Delete failed: ${delErr.message}` }, 500);
      }

      // Optionally delete the author's auth account (permanent ban).
      if ((banUser || body?.action === 'delete_and_ban') && authorId) {
        const { error: banErr } = await supabase.auth.admin.deleteUser(authorId);
        if (banErr) return j({ error: `Ban failed: ${banErr.message}` }, 500);
      }

      // Mark the report resolved.
      await supabase.from('reports').update({ status: 'resolved' }).eq('id', reportId);

      return j({ ok: true, deleted: target_type !== 'user', banned: !!(banUser || body?.action === 'delete_and_ban') });
    }

    // Browse content (posts, comments, threads, replies) with pagination.
    if (body?.action === 'fetch_content') {
      const contentType = body.contentType as string;
      const page = (body.page as number) ?? 0;
      const limit = 30;
      const offset = page * limit;

      const contentCfg: Record<string, { table: string; cols: string }> = {
        post:    { table: 'build_entries', cols: 'id, title, body, created_at, car_id' },
        comment: { table: 'post_comments', cols: 'id, body, created_at, user_id' },
        thread:  { table: 'club_threads',  cols: 'id, title, created_at, user_id' },
        reply:   { table: 'club_replies',  cols: 'id, body, created_at, user_id' },
      };
      const cfg = contentCfg[contentType];
      if (!cfg) return j({ error: `Unknown contentType: ${contentType}` }, 400);

      const { data: rows, error: fetchErr } = await supabase
        .from(cfg.table)
        .select(cfg.cols)
        .order('created_at', { ascending: false })
        .range(offset, offset + limit - 1);
      if (fetchErr) return j({ error: fetchErr.message }, 500);

      // Enrich with author username.
      const enriched = await Promise.all((rows ?? []).map(async (row: any) => {
        let authorId: string | null = null;
        if (contentType === 'post') {
          const { data: car } = await supabase.from('cars').select('owner_id').eq('id', row.car_id).single();
          authorId = car?.owner_id ?? null;
        } else {
          authorId = row.user_id ?? null;
        }
        let username = 'unknown';
        if (authorId) {
          const { data: prof } = await supabase.from('profiles').select('username').eq('id', authorId).single();
          username = prof?.username ?? 'unknown';
        }
        const preview = (row.title || row.body || row.name || '').slice(0, 200);
        return { id: row.id, preview, created_at: row.created_at, author_id: authorId, username };
      }));

      return j({ items: enriched, page, has_more: (rows ?? []).length === limit });
    }

    // Directly delete a content item by type and id (no report required).
    if (body?.action === 'delete_item') {
      const { contentType, itemId } = body as { contentType: string; itemId: string };
      const deleteTableMap: Record<string, string> = {
        post: 'build_entries', comment: 'post_comments',
        thread: 'club_threads', reply: 'club_replies',
      };
      const table = deleteTableMap[contentType];
      if (!table) return j({ error: `Unknown contentType: ${contentType}` }, 400);
      const { error: delErr } = await supabase.from(table).delete().eq('id', itemId);
      if (delErr) return j({ error: delErr.message }, 500);
      return j({ ok: true });
    }

    // Read receipts for a broadcast — count read vs total in the ±5 min window.
    if (body?.action === 'fetch_read_receipts') {
      const ADMIN_ID = '807e6e7c-ebe7-49d3-b774-ad9a75be86f9';
      const sentAt = body.sentAt as string;
      if (!sentAt) return j({ error: 'sentAt required' }, 400);
      const t = new Date(sentAt);
      const from = new Date(t.getTime() - 5 * 60 * 1000).toISOString();
      const to   = new Date(t.getTime() + 5 * 60 * 1000).toISOString();
      const { data: msgs } = await supabase
        .from('dm_messages')
        .select('read_at')
        .eq('sender_id', ADMIN_ID)
        .gte('created_at', from)
        .lte('created_at', to);
      const total = msgs?.length ?? 0;
      const read  = msgs?.filter((m: any) => m.read_at !== null).length ?? 0;
      return j({ read, total });
    }

    // Full user list with last_sign_in_at from auth layer.
    if (body?.action === 'fetch_users') {
      const page = (body.page as number) ?? 0;
      const perPage = 50;
      const { data: authData, error: authErr } = await supabase.auth.admin.listUsers({
        page: page + 1, // Supabase auth uses 1-based pages
        perPage,
      });
      if (authErr) return j({ error: authErr.message }, 500);

      const userIds = (authData.users ?? []).map((u: any) => u.id);
      const { data: profiles } = userIds.length
        ? await supabase.from('profiles').select('id, username, created_at').in('id', userIds)
        : { data: [] };
      const profileMap: Record<string, any> = Object.fromEntries(
        (profiles ?? []).map((p: any) => [p.id, p])
      );

      const users = (authData.users ?? []).map((u: any) => ({
        id: u.id,
        username: profileMap[u.id]?.username ?? null,
        created_at: profileMap[u.id]?.created_at ?? u.created_at,
        last_sign_in_at: u.last_sign_in_at ?? null,
      }));

      return j({ users, has_more: authData.users.length === perPage });
    }

    // Delete all DMs sent in a broadcast window (±5 min around sentAt).
    if (body?.action === 'recall_broadcast') {
      const ADMIN_ID = '807e6e7c-ebe7-49d3-b774-ad9a75be86f9';
      const sentAt = body.sentAt as string;
      if (!sentAt) return j({ error: 'sentAt required' }, 400);
      const t = new Date(sentAt);
      const from = new Date(t.getTime() - 5 * 60 * 1000).toISOString();
      const to   = new Date(t.getTime() + 5 * 60 * 1000).toISOString();
      const { error: delErr, count } = await supabase
        .from('dm_messages')
        .delete({ count: 'exact' })
        .eq('sender_id', ADMIN_ID)
        .gte('created_at', from)
        .lte('created_at', to);
      if (delErr) return j({ error: delErr.message }, 500);
      return j({ ok: true, deleted: count ?? 0 });
    }

    // Fan-out an announcement notification to every user.
    if (body?.action === 'broadcast') {
      const { title, message: msgBody } = body;
      if (!title?.trim()) return j({ error: 'title is required' }, 400);

      // The admin account that appears as the DM sender.
      const ADMIN_ID = '807e6e7c-ebe7-49d3-b774-ad9a75be86f9';
      const messageText = msgBody?.trim()
        ? `${title.trim()}\n\n${msgBody.trim()}`
        : title.trim();

      // Fetch all profile ids except the admin itself.
      const { data: profiles, error: pErr } = await supabase
        .from('profiles')
        .select('id')
        .neq('id', ADMIN_ID);
      if (pErr) return j({ error: `Profiles fetch failed: ${pErr.message}` }, 500);
      if (!profiles?.length) return j({ ok: true, sent: 0 });

      let sent = 0;
      for (const p of profiles as { id: string }[]) {
        const userId = p.id;
        // dm_threads requires participant_a < participant_b (lexicographic UUID order).
        const [pa, pb] = ADMIN_ID < userId
          ? [ADMIN_ID, userId]
          : [userId, ADMIN_ID];

        // Upsert the thread. If the row already exists Supabase returns no data,
        // so fall back to a select to get the existing thread id.
        let threadId: string | null = null;
        const { data: upserted } = await supabase
          .from('dm_threads')
          .upsert({ participant_a: pa, participant_b: pb }, { onConflict: 'participant_a,participant_b' })
          .select('id')
          .single();
        if (upserted?.id) {
          threadId = upserted.id;
        } else {
          const { data: existing } = await supabase
            .from('dm_threads')
            .select('id')
            .eq('participant_a', pa)
            .eq('participant_b', pb)
            .single();
          threadId = existing?.id ?? null;
        }
        if (!threadId) continue;

        // Insert the message.
        const { error: mErr } = await supabase
          .from('dm_messages')
          .insert({ thread_id: threadId, sender_id: ADMIN_ID, body: messageText });
        if (!mErr) sent++;
      }

      return j({ ok: true, sent });
    }

    // --- Challenge actions ----------------------------------------------------

    if (body?.action === 'fetch_challenges') {
      const { data, error } = await supabase
        .from('challenges')
        .select('*')
        .order('starts_at', { ascending: false });
      if (error) return j({ error: error.message }, 500);
      return j({ challenges: data });
    }

    if (body?.action === 'fetch_challenge_entries') {
      const { tag, starts_at, ends_at } = body;
      const { data, error } = await supabase
        .from('build_entries')
        .select('id, title, body, created_at, tags, car:cars(id, make, model, nickname, photo_url, owner_id), post_media(id, url, kind, position), post_likes(user_id)')
        .contains('tags', [tag])
        .gte('created_at', starts_at)
        .lte('created_at', ends_at)
        .order('created_at', { ascending: false });
      if (error) return j({ error: error.message }, 500);
      return j({ entries: data });
    }

    if (body?.action === 'set_challenge_winner') {
      const { challengeId, entryId, carId } = body;
      const { error } = await supabase
        .from('challenges')
        .update({ winner_entry_id: entryId })
        .eq('id', challengeId);
      if (error) return j({ error: error.message }, 500);
      // Insert badge immediately so it shows on the car detail page.
      if (carId) {
        await supabase.from('car_badges').upsert(
          { car_id: carId, challenge_id: challengeId },
          { onConflict: 'car_id,challenge_id', ignoreDuplicates: true }
        );
      }
      return j({ ok: true });
    }

    if (body?.action === 'create_challenge') {
      const { title, emoji, tag, description, starts_at, ends_at } = body;
      const { data, error } = await supabase
        .from('challenges')
        .insert({ title, emoji: emoji ?? '🏁', tag, description: description ?? '', starts_at, ends_at })
        .select()
        .single();
      if (error) return j({ error: error.message }, 500);
      return j({ challenge: data });
    }

    if (body?.action === 'update_challenge') {
      const { challengeId, title, emoji, tag, description, starts_at, ends_at } = body;
      const { error } = await supabase
        .from('challenges')
        .update({ title, emoji, tag, description, starts_at, ends_at })
        .eq('id', challengeId);
      if (error) return j({ error: error.message }, 500);
      return j({ ok: true });
    }

    if (body?.action === 'delete_challenge') {
      const { challengeId } = body;
      const { error } = await supabase.from('challenges').delete().eq('id', challengeId);
      if (error) return j({ error: error.message }, 500);
      return j({ ok: true });
    }

    // --- Shot theme queue actions -------------------------------------------

    if (body?.action === 'fetch_shot_themes') {
      const { data, error } = await supabase
        .from('shot_themes')
        .select('*')
        .order('queue_position', { ascending: true, nullsFirst: false })
        .order('created_at', { ascending: true });
      if (error) return j({ error: error.message }, 500);
      return j({ themes: data });
    }

    if (body?.action === 'create_shot_theme') {
      const { title, emoji, tag, description } = body;
      // Place at end of queue: max(queue_position) + 1
      const { data: maxRow } = await supabase
        .from('shot_themes')
        .select('queue_position')
        .not('queue_position', 'is', null)
        .order('queue_position', { ascending: false })
        .limit(1)
        .single();
      const nextPos = (maxRow?.queue_position ?? 0) + 1;
      const { data, error } = await supabase
        .from('shot_themes')
        .insert({ title, emoji, tag, description, queue_position: nextPos })
        .select()
        .single();
      if (error) return j({ error: error.message }, 500);
      return j({ theme: data });
    }

    if (body?.action === 'update_shot_theme') {
      const { themeId, title, emoji, tag, description } = body;
      const { error } = await supabase
        .from('shot_themes')
        .update({ title, emoji, tag, description })
        .eq('id', themeId);
      if (error) return j({ error: error.message }, 500);
      return j({ ok: true });
    }

    if (body?.action === 'delete_shot_theme') {
      const { themeId } = body;
      const { error } = await supabase.from('shot_themes').delete().eq('id', themeId);
      if (error) return j({ error: error.message }, 500);
      return j({ ok: true });
    }

    if (body?.action === 'reorder_shot_themes') {
      // orderedIds: string[] — full ordered list of theme IDs
      const { orderedIds } = body as { orderedIds: string[] };
      const updates = orderedIds.map((id: string, i: number) =>
        supabase.from('shot_themes').update({ queue_position: i + 1 }).eq('id', id)
      );
      const results = await Promise.all(updates);
      const failed = results.find(r => r.error);
      if (failed?.error) return j({ error: failed.error.message }, 500);
      return j({ ok: true });
    }

    return j({ error: 'Unknown action' }, 400);
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

    // For each report, fetch a content preview and the reported user's strike count.
    const previewMap: Record<string, { table: string; cols: string[] }> = {
      post:    { table: 'build_entries', cols: ['title', 'body'] },
      comment: { table: 'post_comments', cols: ['body'] },
      thread:  { table: 'club_threads',  cols: ['title'] },
      reply:   { table: 'club_replies',  cols: ['body'] },
      club:    { table: 'clubs',         cols: ['name'] },
    };

    const reports = await Promise.all((reportRows ?? []).map(async (r) => {
      let content_preview: string | null = null;
      let strike_count = 0;
      let subjectUserId: string | null = null;

      if (r.target_type === 'user') {
        subjectUserId = r.target_id;
      } else if (previewMap[r.target_type]) {
        const { table, cols } = previewMap[r.target_type];
        const { data: row } = await supabase
          .from(table).select(cols.join(', ')).eq('id', r.target_id).single();
        if (row) {
          const raw = cols.map((c: string) => row[c]).filter(Boolean).join(' — ');
          content_preview = raw.length > 200 ? raw.slice(0, 200) + '…' : raw;
        }
        subjectUserId = await resolveAuthor(supabase, r.target_type, r.target_id);
      }

      if (subjectUserId) {
        const { data: prof } = await supabase
          .from('profiles').select('strike_count').eq('id', subjectUserId).single();
        strike_count = (prof?.strike_count as number) ?? 0;
      }

      return {
        ...r,
        reporter_username: reporterNames[r.reporter_id] ?? 'unknown',
        content_preview,
        strike_count,
      };
    }));

    // Recent signups for a lightweight growth list.
    const { data: recentSignups } = await supabase
      .from('profiles')
      .select('username, created_at')
      .order('created_at', { ascending: false })
      .limit(10);

    // DB size — queried directly via SQL (no Management API needed).
    const { data: dbSizeRow } = await supabase
      .rpc('get_db_size') as { data: number | null };
    const db_size_bytes = dbSizeRow ?? null;

    // Storage size — sum object sizes from storage.objects.
    const { data: storageSizeRow } = await supabase
      .rpc('get_storage_size') as { data: number | null };
    const storage_size_bytes = storageSizeRow ?? null;

    const usage = {
      db_size_bytes,
      storage_size_bytes,
      limits: FREE_LIMITS,
    };

    return j({
      generated_at: new Date().toISOString(),
      users: { total: totalUsers, new_7d: newUsers7d, new_30d: newUsers30d },
      clubs: { total: totalClubs, public: publicClubs, private: totalClubs - publicClubs },
      content: { cars: totalCars, posts: totalPosts, comments: totalComments, reactions: totalReactions },
      subscribers: { premium: premiumSubs, partner: partnerSubs },
      moderation: { open_reports: openReports },
      reports,
      recent_signups: recentSignups ?? [],
      usage,
    });
  } catch (e) {
    return j({ error: String(e) }, 500);
  }
});
