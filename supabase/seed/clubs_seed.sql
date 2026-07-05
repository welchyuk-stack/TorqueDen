-- Launch club seed: 10 public marque clubs owned by the official `torqueden`
-- account, each with a pinned welcome thread.
--
-- PREREQUISITE: the official account must exist first. Sign up a `torqueden`
-- account in the app and set its username to exactly `torqueden` (Settings →
-- Account), then run this in the Supabase SQL editor. Owner membership is added
-- automatically by the on_club_created trigger (migration 0005).
--
-- Idempotent: re-running won't create duplicate clubs or welcome threads.
-- Note: club NAMES only — no manufacturer logos are used (trademark). Add
-- neutral banner art later via Manage.

do $$
declare
  v_owner uuid;
begin
  select id into v_owner from public.profiles where username = 'torqueden';
  if v_owner is null then
    raise exception
      'No profile with username = torqueden. Create the official account and set its username first.';
  end if;

  -- 1. The 10 marque clubs (skip any already seeded by name for this owner).
  insert into public.clubs (name, description, owner_id, is_private)
  select v.name, v.description, v_owner, false
  from (values
    ('BMW',            'For BMW owners and builds — E30s to G8x M cars, and everything in between.'),
    ('Volkswagen',     'The VW community — Golfs, GTIs, Mk1–Mk8 and the whole family.'),
    ('Audi',           'Audi owners and builds — quattro, RS, S-line and beyond.'),
    ('Mercedes-Benz',  'Mercedes-Benz owners and builds — AMG, classics and daily stars.'),
    ('Ford',           'Ford builds — Fiestas, Focus RS, Mustangs and the blue-oval faithful.'),
    ('Toyota',         'Toyota owners and builds — GR, Supra, AE86 and legendary reliability.'),
    ('Honda',          'Honda owners and builds — VTEC, Type R, Civics and Integras.'),
    ('Nissan',         'Nissan owners and builds — GT-R, Z cars, Silvia and the JDM crew.'),
    ('Subaru',         'Subaru owners and builds — WRX, STI, boxer rumble and all-wheel drive.'),
    ('Mazda',          'Mazda owners and builds — MX-5, rotary RX and Zoom-Zoom.')
  ) as v(name, description)
  where not exists (
    select 1 from public.clubs c
    where c.owner_id = v_owner and c.name = v.name
  );

  -- 2. A pinned welcome thread per seeded club (skip if one already exists).
  insert into public.club_threads (club_id, author_id, title, body, is_pinned)
  select c.id, v_owner,
         'Welcome to the ' || c.name || ' club 👋',
         'This is the home for ' || c.name || ' owners and builds on TorqueDen. '
           || 'Introduce yourself, share your build, ask questions and post your '
           || 'progress. Keep it friendly and on-topic. 🔧',
         true
  from public.clubs c
  where c.owner_id = v_owner
    and c.name in (
      'BMW','Volkswagen','Audi','Mercedes-Benz','Ford',
      'Toyota','Honda','Nissan','Subaru','Mazda'
    )
    and not exists (
      select 1 from public.club_threads t
      where t.club_id = c.id and t.author_id = v_owner and t.is_pinned
    );
end $$;

-- Verify:
--   select c.name, count(t.id) as threads
--   from public.clubs c
--   left join public.club_threads t on t.club_id = c.id
--   where c.owner_id = (select id from public.profiles where username = 'torqueden')
--   group by c.name order by c.name;
