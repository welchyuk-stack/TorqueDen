-- Free-text hashtag array on cars.
-- Tags are stored normalised (lowercase, no leading #) so searches are
-- case-insensitive. A GIN index makes array containment queries fast.

alter table public.cars
  add column if not exists tags text[] not null default '{}';

create index if not exists idx_cars_tags on public.cars using gin(tags);
