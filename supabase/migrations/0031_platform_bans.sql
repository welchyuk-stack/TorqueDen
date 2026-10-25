-- Global platform ban flag on profiles.
-- is_banned = true blocks RLS policies on posts, comments, car_meets, clubs.
alter table public.profiles
  add column if not exists is_banned boolean not null default false;

-- Unique index on username (may already exist via Supabase auth trigger).
create unique index if not exists profiles_username_unique
  on public.profiles (lower(username))
  where username is not null;
