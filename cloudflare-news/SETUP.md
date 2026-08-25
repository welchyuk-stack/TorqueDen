# TorqueDen News Worker — Setup

## Prerequisites
- Cloudflare account (free tier is fine to start)
- `wrangler` authenticated: `npx wrangler login`

## 1. Create the D1 database

```bash
npx wrangler d1 create torqueden-news
```

Copy the `database_id` from the output and paste it into `wrangler.toml`:

```toml
[[d1_databases]]
database_id = "YOUR_ID_HERE"
```

## 2. Apply the schema

```bash
# Local dev database
npx wrangler d1 execute torqueden-news --local --file=schema.sql

# Production database
npx wrangler d1 execute torqueden-news --remote --file=schema.sql
```

## 3. Run locally

```bash
npm run dev
```

The Worker runs at `http://localhost:8787`. Test it:

```
GET http://localhost:8787/news/status       # article/cluster counts
GET http://localhost:8787/news/sources      # list active RSS sources
GET http://localhost:8787/news/ingest       # manually trigger ingest (dev only)
GET http://localhost:8787/news              # all clusters, newest first
GET http://localhost:8787/news?category=racing
GET http://localhost:8787/news?category=racing&subcategory=f1
GET http://localhost:8787/news?category=road_cars&limit=20
```

## 4. Deploy

```bash
npm run deploy
```

The Cron Trigger (`0 * * * *`) fires automatically — the Worker polls all RSS sources once per hour and clusters new stories.

## API reference

### `GET /news`

| Param        | Default | Description                              |
|--------------|---------|------------------------------------------|
| `category`   | —       | `racing` \| `road_cars` \| `modified`   |
| `subcategory`| —       | `f1` \| `nascar` \| `indycar` \| `gt3` \| `drifting` |
| `limit`      | 40      | Max clusters to return (capped at 100)   |
| `before`     | now     | Unix timestamp for pagination cursor     |

Response:
```json
{
  "clusters": [
    {
      "id": "abc123",
      "title": "Mercedes reveals 2025 challenger",
      "summary": "...",
      "thumbnail": "https://...",
      "category": "racing",
      "subcategory": "f1",
      "source_count": 3,
      "last_seen_at": 1700000000,
      "sources": [
        { "name": "Motorsport.com F1", "url": "https://..." },
        { "name": "RaceFans",          "url": "https://..." }
      ]
    }
  ],
  "count": 1
}
```

Pagination: pass `before=<last cluster's last_seen_at>` to fetch the next page.

## Notes

- The `/news/ingest` endpoint is disabled in production (`ENVIRONMENT=production`). Ingestion only runs via the Cron Trigger.
- RSS feed URLs in `schema.sql` should be verified live before first deploy — publishing activity varies by source.
- WRC feed from Motorsport.com needs manual verification before enabling (marked in spec as unconfirmed).
