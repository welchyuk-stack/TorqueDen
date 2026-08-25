// SSR share page for public car builds.
// Served at: torqueden.app/c/{slug}
//
// Deploy:  supabase functions deploy share-page --no-verify-jwt
// Route:   Cloudflare rule: torqueden.app/c/* → this function URL
//          (or CNAME share.torqueden.app → <project>.supabase.co)
//
// The function uses the anon key so it inherits the same public-read RLS
// that already allows guest mode. No new policies needed.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

const db = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

Deno.serve(async (req) => {
  const url = new URL(req.url);

  // Expect path like /share-page/c/{slug}
  const match = url.pathname.match(/\/c\/([^/?#]+)/);
  if (!match) return notFound();
  const slug = match[1];

  // Fetch car — never select lat/lng or location_name.
  const { data: car, error: carErr } = await db
    .from('cars')
    .select(
      'id, make, model, year, chassis_model, nickname, photo_url, description, follower_count, public_slug, share_enabled'
    )
    .eq('public_slug', slug)
    .eq('share_enabled', true)
    .single();

  if (carErr || !car) return notFound(slug);

  // Fetch specs
  const { data: specs } = await db
    .from('car_specs')
    .select('label, value, unit, category')
    .eq('car_id', car.id)
    .order('category')
    .order('label');

  // Fetch 10 most recent build entries (no location columns)
  const { data: entries } = await db
    .from('build_entries')
    .select('id, title, body, category, created_at, tags')
    .eq('car_id', car.id)
    .order('created_at', { ascending: false })
    .limit(10);

  // Record visit (fire-and-forget, non-blocking)
  db.rpc('record_link_visit', { slug }).then(() => {});

  const cardUrl = `${SUPABASE_URL}/storage/v1/object/public/share-cards/${car.id}.png`;
  const title = [car.nickname, `${car.year ?? ''} ${car.make} ${car.model}`.trim()]
    .filter(Boolean)
    .join(' — ');
  const ogTitle = `${title} — TorqueDen`;
  const ogDesc = car.description ||
    (entries ?? []).slice(0, 3).map((e: any) => e.title).join(', ') ||
    `${car.make} ${car.model} build on TorqueDen`;

  const html = page({
    car,
    specs: specs ?? [],
    entries: entries ?? [],
    cardUrl,
    ogTitle,
    ogDesc,
    slug,
  });

  return new Response(html, {
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=300',
    },
  });
});

// ── 404 ──────────────────────────────────────────────────────────────────────

function notFound(slug?: string) {
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Build not found — TorqueDen</title>
${styles()}
</head>
<body>
<div class="not-found">
  <div class="wordmark"><span class="white">Torque</span><span class="ember">Den</span></div>
  <h1>Build not found</h1>
  <p>This link may have expired or the owner made it private.</p>
  <a class="cta" href="https://apps.apple.com/us/app/torqueden-car-builds-mods/id6788811379" target="_blank">
    Get TorqueDen — Free on the App Store
  </a>
</div>
</body>
</html>`;
  return new Response(html, {
    status: 404,
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  });
}

// ── Full page ─────────────────────────────────────────────────────────────────

function page({ car, specs, entries, cardUrl, ogTitle, ogDesc, slug }: {
  car: any;
  specs: any[];
  entries: any[];
  cardUrl: string;
  ogTitle: string;
  ogDesc: string;
  slug: string;
}) {
  const carTitle = [car.nickname, `${car.year ?? ''} ${car.make} ${car.model}`.trim()]
    .filter(Boolean)
    .join(' — ');

  const specsHtml = specs.length
    ? `<section class="section">
        <h2>Specs</h2>
        <dl class="specs-grid">
          ${specs.map((s: any) => `
            <div class="spec-row">
              <dt>${esc(s.label)}</dt>
              <dd>${esc(s.value)}${s.unit ? `<span class="unit"> ${esc(s.unit)}</span>` : ''}</dd>
            </div>`).join('')}
        </dl>
      </section>`
    : '';

  const entriesHtml = entries.length
    ? `<section class="section">
        <h2>Build log</h2>
        ${entries.map((e: any) => `
          <div class="entry">
            ${e.category ? `<div class="entry-cat">${esc(e.category)}</div>` : ''}
            <div class="entry-title">${esc(e.title)}</div>
            ${e.body ? `<div class="entry-body">${esc(e.body)}</div>` : ''}
            <div class="entry-date">${fmtDate(e.created_at)}</div>
          </div>`).join('')}
      </section>`
    : '';

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(ogTitle)}</title>

<!-- OG / Twitter card -->
<meta property="og:title" content="${esc(ogTitle)}">
<meta property="og:description" content="${esc(ogDesc)}">
<meta property="og:image" content="${esc(cardUrl)}">
<meta property="og:image:width" content="1080">
<meta property="og:image:height" content="1350">
<meta property="og:type" content="website">
<meta property="og:url" content="https://torqueden.app/c/${esc(slug)}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(ogTitle)}">
<meta name="twitter:description" content="${esc(ogDesc)}">
<meta name="twitter:image" content="${esc(cardUrl)}">

${styles()}
</head>
<body>

<!-- Header -->
<header>
  <div class="wordmark"><span class="white">Torque</span><span class="ember">Den</span></div>
</header>

<!-- Hero -->
<div class="hero">
  ${car.photo_url
    ? `<img class="hero-photo" src="${esc(car.photo_url)}" alt="${esc(carTitle)}">`
    : '<div class="hero-no-photo"></div>'}
  <div class="hero-overlay">
    <h1 class="hero-title">${esc(car.nickname || `${car.make} ${car.model}`)}</h1>
    <p class="hero-sub">${esc([car.year, car.make, car.model, car.chassis_model ? `· ${car.chassis_model}` : ''].filter(Boolean).join(' '))}</p>
    ${car.follower_count > 0
      ? `<div class="follower-badge">${car.follower_count} follower${car.follower_count === 1 ? '' : 's'}</div>`
      : ''}
  </div>
</div>

<!-- Build content -->
<main class="content">
  ${car.description ? `<section class="section"><p class="car-desc">${esc(car.description)}</p></section>` : ''}
  ${specsHtml}
  ${entriesHtml}
</main>

<!-- Sticky CTA -->
<div class="sticky-cta">
  <a class="cta" href="https://apps.apple.com/us/app/torqueden-car-builds-mods/id6788811379" target="_blank">
    Get TorqueDen — Free on the App Store
  </a>
</div>

</body>
</html>`;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function esc(s: unknown): string {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function fmtDate(iso: string): string {
  try {
    return new Date(iso).toLocaleDateString('en-GB', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
    });
  } catch {
    return '';
  }
}

function styles(): string {
  return `<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html{font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;background:#111;color:#e8e4de;-webkit-text-size-adjust:100%}
body{max-width:640px;margin:0 auto;padding-bottom:80px}

header{display:flex;align-items:center;padding:16px 20px;border-bottom:1px solid #2a2a2a}
.wordmark{font-size:22px;font-weight:800;letter-spacing:-0.3px}
.white{color:#e8e4de}.ember{color:#FF6A2B}

.hero{position:relative;width:100%;aspect-ratio:4/3;overflow:hidden;background:#1a1a1a}
.hero-photo{width:100%;height:100%;object-fit:cover;display:block}
.hero-no-photo{width:100%;height:100%;background:linear-gradient(135deg,#2a2a2a,#111)}
.hero-overlay{position:absolute;bottom:0;left:0;right:0;padding:20px;background:linear-gradient(transparent,rgba(0,0,0,.75))}
.hero-title{font-size:26px;font-weight:800;color:#fff;line-height:1.15;letter-spacing:-0.3px}
.hero-sub{font-size:13px;color:#aaa;margin-top:4px}
.follower-badge{display:inline-block;margin-top:8px;padding:4px 10px;border-radius:20px;font-size:12px;font-weight:600;color:#FF6A2B;background:rgba(255,106,43,.12);border:1px solid rgba(255,106,43,.3)}

.content{padding:0 20px}
.section{margin-top:28px}
.section h2{font-size:16px;font-weight:700;color:#fff;margin-bottom:12px;text-transform:uppercase;letter-spacing:.05em}

.car-desc{font-size:14px;line-height:1.6;color:#bbb}

.specs-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.spec-row{background:#1e1e1e;border-radius:10px;padding:10px 12px}
.spec-row dt{font-size:11px;color:#888;text-transform:uppercase;letter-spacing:.04em;margin-bottom:2px}
.spec-row dd{font-size:14px;font-weight:600;color:#e8e4de}
.unit{font-size:12px;font-weight:400;color:#888}

.entry{border-left:3px solid #FF6A2B;padding:8px 12px;margin-bottom:10px;background:#1a1a1a;border-radius:0 8px 8px 0}
.entry-cat{font-size:10px;text-transform:uppercase;letter-spacing:.06em;color:#FF6A2B;margin-bottom:2px}
.entry-title{font-size:14px;font-weight:600;color:#e8e4de}
.entry-body{font-size:13px;color:#999;margin-top:4px;line-height:1.5}
.entry-date{font-size:11px;color:#666;margin-top:4px}

.sticky-cta{position:fixed;bottom:0;left:0;right:0;padding:14px 20px;background:linear-gradient(transparent,rgba(17,17,17,.98));display:flex;justify-content:center}
.cta{display:inline-block;padding:14px 28px;background:#FF6A2B;color:#2A0F04;font-weight:700;font-size:15px;border-radius:12px;text-decoration:none;text-align:center}

.not-found{display:flex;flex-direction:column;align-items:center;justify-content:center;min-height:100vh;gap:16px;padding:20px;text-align:center}
.not-found h1{font-size:22px;font-weight:700;color:#e8e4de}
.not-found p{color:#888;font-size:14px}
.not-found .cta{margin-top:12px}
</style>`;
}
