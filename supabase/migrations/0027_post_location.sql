-- Optional free-text location tag on a post, e.g. "Nürburgring" or "Manchester, UK".
alter table public.build_entries
  add column if not exists location_name text check (char_length(trim(location_name)) <= 100);
