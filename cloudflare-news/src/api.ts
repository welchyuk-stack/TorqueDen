// REST API handlers — all responses are JSON.

interface Cluster {
  id: string;
  title: string;
  summary: string | null;
  thumbnail: string | null;
  category: string;
  subcategory: string | null;
  source_count: number;
  last_seen_at: number;
  sources: Array<{ name: string; url: string }>;
}

// GET /news?category=racing&subcategory=f1&limit=40&before=<unix>
export async function handleFeed(db: D1Database, url: URL): Promise<Response> {
  const category    = url.searchParams.get('category');     // optional filter
  const subcategory = url.searchParams.get('subcategory');  // optional filter
  const limit       = Math.min(parseInt(url.searchParams.get('limit') ?? '40'), 100);
  const before      = parseInt(url.searchParams.get('before') ?? '0') || Math.floor(Date.now() / 1000);

  let query: string;
  let bindings: unknown[];

  if (category && subcategory) {
    query = `
      SELECT c.*, GROUP_CONCAT(s.name || '|' || a.url, '~~') AS src_list
      FROM clusters c
      JOIN articles a ON a.cluster_id = c.id
      JOIN sources s ON s.id = a.source_id
      WHERE c.category = ? AND c.subcategory = ? AND c.last_seen_at < ?
      GROUP BY c.id
      ORDER BY c.last_seen_at DESC
      LIMIT ?
    `;
    bindings = [category, subcategory, before, limit];
  } else if (category) {
    query = `
      SELECT c.*, GROUP_CONCAT(s.name || '|' || a.url, '~~') AS src_list
      FROM clusters c
      JOIN articles a ON a.cluster_id = c.id
      JOIN sources s ON s.id = a.source_id
      WHERE c.category = ? AND c.last_seen_at < ?
      GROUP BY c.id
      ORDER BY c.last_seen_at DESC
      LIMIT ?
    `;
    bindings = [category, before, limit];
  } else {
    query = `
      SELECT c.*, GROUP_CONCAT(s.name || '|' || a.url, '~~') AS src_list
      FROM clusters c
      JOIN articles a ON a.cluster_id = c.id
      JOIN sources s ON s.id = a.source_id
      WHERE c.last_seen_at < ?
      GROUP BY c.id
      ORDER BY c.last_seen_at DESC
      LIMIT ?
    `;
    bindings = [before, limit];
  }

  const stmt = db.prepare(query);
  const result = await stmt.bind(...bindings).all<Record<string, unknown>>();

  const clusters: Cluster[] = result.results.map(row => {
    const srcList = (row['src_list'] as string | null) ?? '';
    const sources = srcList
      ? srcList.split('~~').map(entry => {
          const [name, articleUrl] = entry.split('|');
          return { name, url: articleUrl };
        })
      : [];
    return {
      id:           row['id'] as string,
      title:        row['title'] as string,
      summary:      row['summary'] as string | null,
      thumbnail:    row['thumbnail'] as string | null,
      category:     row['category'] as string,
      subcategory:  row['subcategory'] as string | null,
      source_count: row['source_count'] as number,
      last_seen_at: row['last_seen_at'] as number,
      sources,
    };
  });

  return json({ clusters, count: clusters.length });
}

// GET /news/sources — list all active sources
export async function handleSources(db: D1Database): Promise<Response> {
  const result = await db.prepare('SELECT id, name, category, subcategory FROM sources WHERE active = 1 ORDER BY category, subcategory, name').all();
  return json({ sources: result.results });
}

// GET /news/status — health check / last-ingest info
export async function handleStatus(db: D1Database): Promise<Response> {
  const articleCount = await db.prepare('SELECT COUNT(*) as n FROM articles').first<{ n: number }>();
  const clusterCount = await db.prepare('SELECT COUNT(*) as n FROM clusters').first<{ n: number }>();
  const latest = await db.prepare('SELECT MAX(fetched_at) as t FROM articles').first<{ t: number | null }>();
  return json({
    articles: articleCount?.n ?? 0,
    clusters: clusterCount?.n ?? 0,
    last_fetched_at: latest?.t ?? null,
  });
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'public, max-age=60',
    },
  });
}
