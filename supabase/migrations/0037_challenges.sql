-- Weekly Challenges feature.

create table if not exists public.challenges (
  id                  uuid primary key default gen_random_uuid(),
  title               text not null,
  emoji               text not null default '🏁',
  tag                 text not null unique,
  description         text not null default '',
  starts_at           timestamptz not null,
  ends_at             timestamptz not null,
  winner_entry_id     uuid references public.build_entries(id) on delete set null,
  winner_announced    boolean not null default false,
  created_at          timestamptz not null default now(),
  constraint challenge_window check (ends_at > starts_at)
);

create index if not exists idx_challenges_window on public.challenges (starts_at, ends_at);

create table if not exists public.car_badges (
  car_id          uuid not null references public.cars(id) on delete cascade,
  challenge_id    uuid not null references public.challenges(id) on delete cascade,
  awarded_at      timestamptz not null default now(),
  primary key (car_id, challenge_id)
);

alter table public.challenges enable row level security;
alter table public.car_badges enable row level security;

create policy "challenges public read" on public.challenges for select using (true);
create policy "badges public read"     on public.car_badges  for select using (true);

grant select on public.challenges, public.car_badges to anon, authenticated;

alter table public.notification_prefs
  add column if not exists challenge_updates boolean not null default true;

-- Seed first 8 weekly challenges (Fri 18:00 BST / 17:00 UTC → following Fri 17:00 UTC).
insert into public.challenges (title, emoji, tag, description, starts_at, ends_at) values
  ('Engine Bay Week',              '🔧', 'enginebayweek',        'Show us what''s under the bonnet. Stock, tuned, swapped — we want it all.',                  '2026-07-25 17:00:00+00', '2026-08-01 17:00:00+00'),
  ('Stock vs Now',                 '📸', 'stockvsnow',           'Post your oldest photo next to where the build is today. The glow-up.',                      '2026-08-01 17:00:00+00', '2026-08-08 17:00:00+00'),
  ('Night Shots',                  '🌙', 'nightshots',           'Your car after dark. Light trails, moody shadows, neon reflections — make it atmospheric.',  '2026-08-08 17:00:00+00', '2026-08-15 17:00:00+00'),
  ('Wheel Wednesday, All Week',    '🛞', 'wheelweek',            'Wheels and fitment. Show us the stance, the lip, the offset.',                              '2026-08-15 17:00:00+00', '2026-08-22 17:00:00+00'),
  ('Under £500 Club',             '💷', 'under500club',         'Best cheap mod you''ve done. Prove expensive isn''t always better.',                         '2026-08-22 17:00:00+00', '2026-08-29 17:00:00+00'),
  ('Daily Driver Appreciation',    '🚗', 'dailydriver',          'The one that does the miles. Unglamorous and essential — show it some love.',                '2026-08-29 17:00:00+00', '2026-09-05 17:00:00+00'),
  ('Worst Weather',                '🌧', 'worstweather',         'Driven in it, not garaged. Rain, fog, mud — if you braved it, post it.',                    '2026-09-05 17:00:00+00', '2026-09-12 17:00:00+00'),
  ('The Detail Shot',              '🔍', 'detailshot',           'One close-up that tells the story. Badge, stitch, welds, carbon — whatever defines it.',   '2026-09-12 17:00:00+00', '2026-09-19 17:00:00+00')
on conflict (tag) do nothing;
