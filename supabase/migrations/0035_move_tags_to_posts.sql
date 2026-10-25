-- Move tags from cars to build_entries.
-- Tags belong to individual posts, not the whole car.

alter table public.build_entries
  add column if not exists tags text[] not null default '{}';

create index if not exists idx_build_entries_tags on public.build_entries using gin(tags);

-- Remove from cars (applied in 0034 — safe to drop now).
alter table public.cars drop column if exists tags;
drop index if exists idx_cars_tags;
