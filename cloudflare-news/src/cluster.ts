// Heuristic story clustering: two articles are the same story if they share
// at least 2 significant proper-noun tokens AND were published within 6 hours.

const WINDOW_SECONDS = 6 * 60 * 60;
const MIN_SHARED_TOKENS = 2;

// Words that don't count as discriminating tokens.
const STOPWORDS = new Set([
  'the','a','an','and','or','but','in','on','at','to','for','of','with',
  'by','from','is','are','was','were','be','been','has','have','had',
  'will','would','could','should','may','might','can','do','did','does',
  'new','says','said','after','over','up','out','as','into','about',
  'car','cars','race','racing','team','driver','season','year','day',
  'news','report','update','latest','first','second','third',
]);

export function fingerprintTitle(title: string): string[] {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .filter(w => w.length >= 3 && !STOPWORDS.has(w));
}

export function sharedTokenCount(a: string[], b: string[]): number {
  const setA = new Set(a);
  return b.filter(t => setA.has(t)).length;
}

export function withinWindow(pubA: number, pubB: number): boolean {
  return Math.abs(pubA - pubB) <= WINDOW_SECONDS;
}

export function isSameStory(
  titleA: string, pubA: number,
  titleB: string, pubB: number,
): boolean {
  if (!withinWindow(pubA, pubB)) return false;
  const tokA = fingerprintTitle(titleA);
  const tokB = fingerprintTitle(titleB);
  return sharedTokenCount(tokA, tokB) >= MIN_SHARED_TOKENS;
}

// Stable cluster ID: sha256 of the earliest article URL in the cluster.
// Computed once when the cluster is first created; subsequent articles
// that join the cluster inherit the existing cluster_id.
export async function makeClusterId(canonicalUrl: string): Promise<string> {
  const enc = new TextEncoder();
  const buf = await crypto.subtle.digest('SHA-256', enc.encode(canonicalUrl));
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('').slice(0, 16);
}

export async function makeArticleId(url: string): Promise<string> {
  const enc = new TextEncoder();
  const buf = await crypto.subtle.digest('SHA-256', enc.encode(url));
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('').slice(0, 16);
}
