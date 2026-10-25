export interface RssItem {
  title: string;
  url: string;
  summary: string | null;
  thumbnail: string | null;
  publishedAt: number; // unix seconds
}

// Minimal hand-rolled RSS/Atom parser — avoids a DOM dependency in Workers.
export async function fetchFeed(feedUrl: string): Promise<RssItem[]> {
  const res = await fetch(feedUrl, {
    headers: { 'User-Agent': 'TorqueDen-News/1.0 (+https://torqueden.app)' },
    cf: { cacheTtl: 300 },
  });
  if (!res.ok) return [];
  const xml = await res.text();
  return parseXml(xml);
}

function parseXml(xml: string): RssItem[] {
  const items: RssItem[] = [];
  // Match RSS <item> or Atom <entry> blocks
  const itemRe = /<item[\s>]([\s\S]*?)<\/item>|<entry[\s>]([\s\S]*?)<\/entry>/gi;
  let m: RegExpExecArray | null;
  while ((m = itemRe.exec(xml)) !== null) {
    const block = m[1] ?? m[2];
    const item = parseItem(block);
    if (item) items.push(item);
  }
  return items;
}

function parseItem(block: string): RssItem | null {
  const title = extractText(block, 'title');
  const url = extractUrl(block);
  if (!title || !url) return null;

  const pubDate = extractText(block, 'pubDate') ?? extractText(block, 'published') ?? extractText(block, 'updated');
  const publishedAt = pubDate ? Math.floor(new Date(pubDate).getTime() / 1000) : Math.floor(Date.now() / 1000);
  if (isNaN(publishedAt)) return null;

  const summary = extractSummary(block);
  const thumbnail = extractThumbnail(block);

  return { title: decodeEntities(title.trim()), url: url.trim(), summary, thumbnail, publishedAt };
}

function extractText(block: string, tag: string): string | null {
  const re = new RegExp(`<${tag}[^>]*>(?:<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>|([\\s\\S]*?))<\\/${tag}>`, 'i');
  const m = re.exec(block);
  if (!m) return null;
  return (m[1] ?? m[2] ?? '').trim() || null;
}

function extractUrl(block: string): string | null {
  // Prefer <link href="..."> (Atom), then <link>URL</link> (RSS)
  const atomLink = /<link[^>]+href="([^"]+)"/i.exec(block);
  if (atomLink) return atomLink[1];
  const rssLink = extractText(block, 'link');
  if (rssLink && rssLink.startsWith('http')) return rssLink;
  const guid = extractText(block, 'guid');
  if (guid && guid.startsWith('http')) return guid;
  return null;
}

function extractSummary(block: string): string | null {
  const raw = extractText(block, 'description') ?? extractText(block, 'summary') ?? extractText(block, 'content');
  if (!raw) return null;
  // Strip HTML tags and collapse whitespace
  const stripped = raw.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
  return stripped.slice(0, 300) || null;
}

function extractThumbnail(block: string): string | null {
  // <media:thumbnail url="...">
  const mediaThumbnail = /media:thumbnail[^>]+url="([^"]+)"/i.exec(block);
  if (mediaThumbnail) return mediaThumbnail[1];
  // <enclosure url="..." type="image/...">
  const enclosure = /<enclosure[^>]+url="([^"]+)"[^>]+type="image\/[^"]+"/i.exec(block) ??
                    /<enclosure[^>]+type="image\/[^"]+"[^>]+url="([^"]+)"/i.exec(block);
  if (enclosure) return enclosure[1];
  // <media:content url="...">
  const mediaContent = /media:content[^>]+url="([^"]+)"/i.exec(block);
  if (mediaContent) return mediaContent[1];
  // First <img src="..."> inside description
  const img = /<img[^>]+src="([^"]+)"/i.exec(block);
  if (img) return img[1];
  return null;
}

function decodeEntities(s: string): string {
  return s
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'");
}
