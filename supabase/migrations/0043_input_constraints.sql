-- Server-side bounds on user-submitted text.
--
-- Validation up to now lived only in the Flutter form validators, which stop
-- honest mistakes but not a direct PostgREST call — nothing prevented a
-- scripted client from writing a 10MB bio or a username full of control
-- characters. These CHECKs are the copy the database enforces regardless of
-- how the row arrives.
--
-- Limits were chosen against the live data (max username 13, display_name 6,
-- bio 25, post title 34, body 61, car model 24) so every existing row passes
-- and there is generous headroom.
--
-- The username charset deliberately allows '.' and '-': one live account
-- already uses a dot, and auth_screen.dart only rejects spaces, so a stricter
-- rule would lock that user out of editing their own profile.
--
-- Note: CHECK constraints cannot contain subqueries, so per-element tag
-- validation is expressed as a bound on the joined string rather than an
-- unnest over the array.

-- ── profiles ───────────────────────────────────────────────────────────────
alter table public.profiles
  drop constraint if exists profiles_username_valid,
  add constraint profiles_username_valid
    check (username is null or username ~ '^[A-Za-z0-9._-]{3,30}$');

alter table public.profiles
  drop constraint if exists profiles_display_name_len,
  add constraint profiles_display_name_len
    check (display_name is null or length(display_name) <= 50);

alter table public.profiles
  drop constraint if exists profiles_bio_len,
  add constraint profiles_bio_len
    check (bio is null or length(bio) <= 300);

-- ── build_entries (posts and build-log updates) ────────────────────────────
alter table public.build_entries
  drop constraint if exists build_entries_title_len,
  add constraint build_entries_title_len
    check (title is null or length(title) <= 120);

alter table public.build_entries
  drop constraint if exists build_entries_body_len,
  add constraint build_entries_body_len
    check (body is null or length(body) <= 5000);

alter table public.build_entries
  drop constraint if exists build_entries_tags_bounded,
  add constraint build_entries_tags_bounded
    check (
      tags is null
      or (coalesce(array_length(tags, 1), 0) <= 10
          and length(array_to_string(tags, ',')) <= 300)
    );

-- ── cars ───────────────────────────────────────────────────────────────────
alter table public.cars
  drop constraint if exists cars_text_len,
  add constraint cars_text_len
    check (
      (make is null or length(make) <= 50)
      and (model is null or length(model) <= 50)
      and (nickname is null or length(nickname) <= 50)
      and (chassis_model is null or length(chassis_model) <= 50)
    );
