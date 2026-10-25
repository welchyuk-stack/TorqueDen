-- Car meets: public events anyone can create and RSVP to.
create table public.car_meets (
  id            uuid primary key default gen_random_uuid(),
  creator_id    uuid not null references public.profiles(id) on delete cascade,
  title         text not null check (char_length(trim(title)) between 3 and 100),
  description   text check (char_length(trim(description)) <= 2000),
  location_name text not null check (char_length(trim(location_name)) between 2 and 200),
  latitude      double precision,
  longitude     double precision,
  meet_at       timestamptz not null,
  cover_url     text,
  created_at    timestamptz not null default now()
);

create index on public.car_meets (meet_at);
create index on public.car_meets (creator_id);

alter table public.car_meets enable row level security;

create policy "Anyone can view meets" on public.car_meets
  for select using (true);

create policy "Authenticated users can create meets" on public.car_meets
  for insert with check (auth.uid() = creator_id);

create policy "Creator can update meet" on public.car_meets
  for update using (auth.uid() = creator_id);

create policy "Creator can delete meet" on public.car_meets
  for delete using (auth.uid() = creator_id);

-- RSVPs: going or maybe. One row per (user, meet). Upsert to change status.
create table public.meet_rsvps (
  meet_id    uuid not null references public.car_meets(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  status     text not null check (status in ('going', 'maybe')),
  created_at timestamptz not null default now(),
  primary key (meet_id, user_id)
);

alter table public.meet_rsvps enable row level security;

create policy "Anyone can view RSVPs" on public.meet_rsvps
  for select using (true);

create policy "Users manage own RSVP" on public.meet_rsvps
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
