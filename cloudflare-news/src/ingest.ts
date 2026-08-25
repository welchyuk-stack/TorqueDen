import { fetchFeed, RssItem } from './rss';
import { isSameStory, makeArticleId, makeClusterId } from './cluster';

interface Source {
  id: string;
  name: string;
  feed_url: string;
  category: string;
  subcategory: string | null;
}

interface StoredCluster {
  id: string;
  title: string;
  summary: string | null;
  thumbnail: string | null;
  category: string;
  subcategory: string | null;
  source_count: number;
  first_seen_at: number;
  last_seen_at: number;
}

export async function runIngest(db: D1Database): Promise<{ ingested: number; clusters: number }> {
  const sources = await db.prepare('SELECT * FROM sources WHERE active = 1').all<Source>();
  if (!sources.results.length) return { ingested: 0, clusters: 0 };

  let totalIngested = 0;
  let totalClusters = 0;

  for (const source of sources.results) {
    const items = await fetchFeed(source.feed_url);
    const { ingested, clusters } = await ingestItems(db, source, items);
    totalIngested += ingested;
    totalClusters += clusters;
  }

  return { ingested: totalIngested, clusters: totalClusters };
}

async function ingestItems(
  db: D1Database,
  source: Source,
  items: RssItem[],
): Promise<{ ingested: number; clusters: number }> {
  const now = Math.floor(Date.now() / 1000);
  let ingested = 0;
  let newClusters = 0;

  // Load recent clusters for this category to match against (last 12h window).
  const cutoff = now - 12 * 60 * 60;
  const existingClusters = await db
    .prepare('SELECT * FROM clusters WHERE category = ? AND last_seen_at >= ? ORDER BY last_seen_at DESC LIMIT 200')
    .bind(source.category, cutoff)
    .all<StoredCluster>();

  for (const item of items) {
    const articleId = await makeArticleId(item.url);

    // Skip already-ingested articles.
    const existing = await db
      .prepare('SELECT id FROM articles WHERE id = ?')
      .bind(articleId)
      .first<{ id: string }>();
    if (existing) continue;

    // Find a matching cluster.
    let clusterId: string | null = null;
    for (const cluster of existingClusters.results) {
      if (isSameStory(item.title, item.publishedAt, cluster.title, cluster.first_seen_at)) {
        clusterId = cluster.id;
        break;
      }
    }

    if (!clusterId) {
      // Create a new cluster seeded by this article.
      clusterId = await makeClusterId(item.url);
      await db.prepare(`
        INSERT OR IGNORE INTO clusters (id, title, summary, thumbnail, category, subcategory, source_count, first_seen_at, last_seen_at)
        VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
      `).bind(
        clusterId, item.title, item.summary, item.thumbnail,
        source.category, source.subcategory,
        item.publishedAt, item.publishedAt,
      ).run();
      newClusters++;
      existingClusters.results.push({
        id: clusterId,
        title: item.title,
        summary: item.summary,
        thumbnail: item.thumbnail,
        category: source.category,
        subcategory: source.subcategory,
        source_count: 1,
        first_seen_at: item.publishedAt,
        last_seen_at: item.publishedAt,
      });
    } else {
      // Update existing cluster's source count and recency.
      await db.prepare(`
        UPDATE clusters
        SET source_count = source_count + 1,
            last_seen_at = MAX(last_seen_at, ?)
        WHERE id = ?
      `).bind(item.publishedAt, clusterId).run();
    }

    await db.prepare(`
      INSERT OR IGNORE INTO articles (id, source_id, title, summary, thumbnail, url, published_at, fetched_at, category, subcategory, cluster_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      articleId, source.id, item.title, item.summary, item.thumbnail,
      item.url, item.publishedAt, now,
      source.category, source.subcategory, clusterId,
    ).run();

    ingested++;
  }

  return { ingested, clusters: newClusters };
}
