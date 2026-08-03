-- Shot theme queue: ordered list of upcoming "The Shot" weekly challenge themes.
-- queue_position determines order (lower = sooner). NULL = archived/unused.

create table if not exists shot_themes (
  id              uuid primary key default gen_random_uuid(),
  title           text not null,
  emoji           text not null default '📸',
  tag             text not null,
  description     text not null default '',
  queue_position  integer,
  created_at      timestamptz not null default now()
);

-- Only admins interact with this table via the edge function (service role key),
-- so no RLS needed — but lock it down to be safe.
alter table shot_themes enable row level security;
create policy "No public access" on shot_themes for all using (false);
