import { runIngest } from './ingest';
import { handleFeed, handleSources, handleStatus } from './api';

export interface Env {
  DB: D1Database;
  ENVIRONMENT: string;
}

export default {
  // HTTP handler — serves the news API.
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
        },
      });
    }

    if (request.method !== 'GET') {
      return new Response('Method not allowed', { status: 405 });
    }

    const path = url.pathname.replace(/\/$/, '');

    if (path === '/news' || path === '') {
      return handleFeed(env.DB, url);
    }
    if (path === '/news/sources') {
      return handleSources(env.DB);
    }
    if (path === '/news/status') {
      return handleStatus(env.DB);
    }
    // Admin: manual ingest trigger (useful during dev/debugging)
    if (path === '/news/ingest' && env.ENVIRONMENT !== 'production') {
      const result = await runIngest(env.DB);
      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    return new Response('Not found', { status: 404 });
  },

  // Cron handler — runs every hour per wrangler.toml trigger.
  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(runIngest(env.DB));
  },
};
