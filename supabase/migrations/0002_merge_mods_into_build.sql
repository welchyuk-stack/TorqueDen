-- Merge Mods into the Build timeline.
--
-- Mods become date-stamped build entries with an optional category tag, so the
-- app can drop the separate Mods tab. This:
--   1. adds a nullable `category` column to build_entries, and
--   2. back-fills existing mods rows as (silent) build entries, preserving
--      their category, name, notes and original timestamp.
--
-- The mods table itself is left in place (unused by the app) so this is
-- reversible; it can be dropped later once you're happy.

-- 1. Optional category tag on build entries (e.g. "Exhaust", "Suspension").
alter table public.build_entries
  add column if not exists category text;

-- 2. Back-fill mods as build entries. The NOT EXISTS guard makes this safe to
--    re-run: a mod already migrated (same car, title and timestamp) is skipped.
insert into public.build_entries (car_id, title, body, category, created_at, silent)
select m.car_id, m.name, m.notes, m.category, m.created_at, true
from public.mods m
where not exists (
  select 1 from public.build_entries b
  where b.car_id = m.car_id
    and b.title = m.name
    and b.created_at = m.created_at
);
