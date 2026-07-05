-- House ads: native sponsored posts woven into the Home feed. Self-served —
-- rows are created via the dashboard / service role, never by app clients.
-- Free tier sees them; Premium/Partner get an ad-free feed (enforced app-side).

create table if not exists public.sponsored_posts (
  id                    uuid primary key default gen_random_uuid(),
  advertiser_name       text not null,
  advertiser_avatar_url text,
  headline              text not null,
  body                  text,
  media_url             text,
  media_kind            text,                       -- 'image' | 'video' | null
  cta_label             text not null default 'Learn more',
  cta_url               text not null,
  active                boolean not null default true,
  weight                integer not null default 1, -- higher = surfaced more
  starts_at             timestamptz,                -- optional schedule window
  ends_at               timestamptz,
  created_at            timestamptz not null default now()
);
create index if not exists sponsored_posts_active_idx on public.sponsored_posts (active, weight desc);

grant select on public.sponsored_posts to anon, authenticated;
alter table public.sponsored_posts enable row level security;

-- Public read of active ads only. No client insert/update/delete — managed via
-- the dashboard / service role.
create policy "Active sponsored posts are viewable" on public.sponsored_posts
  for select using (active = true);
