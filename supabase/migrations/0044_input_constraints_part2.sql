-- Extends 0043's server-side text bounds to the remaining user-input tables:
-- clubs, club threads/replies, meets, DMs and post comments.
--
-- Held back from 0043 only because the column names hadn't been verified
-- against the live schema; they have been now (information_schema), and limits
-- are set well above the largest live values (meet title 18, location 19,
-- address 26) so no existing row is affected.
--
-- URL columns are length-bounded rather than pattern-matched. They're written
-- by the app after an upload, but a direct PostgREST call could set anything,
-- and a length cap is the part that can't break legitimate existing rows.

-- ── clubs ──────────────────────────────────────────────────────────────────
alter table public.clubs
  drop constraint if exists clubs_text_len,
  add constraint clubs_text_len
    check (
      (name is null or length(name) <= 60)
      and (description is null or length(description) <= 1000)
      and (rules is null or length(rules) <= 5000)
      and (avatar_url is null or length(avatar_url) <= 500)
      and (banner_url is null or length(banner_url) <= 500)
    );

-- ── club forum ─────────────────────────────────────────────────────────────
alter table public.club_threads
  drop constraint if exists club_threads_text_len,
  add constraint club_threads_text_len
    check (
      (title is null or length(title) <= 200)
      and (body is null or length(body) <= 10000)
    );

alter table public.club_replies
  drop constraint if exists club_replies_body_len,
  add constraint club_replies_body_len
    check (body is null or length(body) <= 10000);

-- ── meets ──────────────────────────────────────────────────────────────────
alter table public.car_meets
  drop constraint if exists car_meets_text_len,
  add constraint car_meets_text_len
    check (
      (title is null or length(title) <= 120)
      and (description is null or length(description) <= 5000)
      and (location_name is null or length(location_name) <= 120)
      and (address is null or length(address) <= 200)
      and (cover_url is null or length(cover_url) <= 500)
    );

-- ── direct messages ────────────────────────────────────────────────────────
alter table public.dm_messages
  drop constraint if exists dm_messages_body_len,
  add constraint dm_messages_body_len
    check (body is null or length(body) <= 4000);

-- ── post comments ──────────────────────────────────────────────────────────
alter table public.post_comments
  drop constraint if exists post_comments_body_len,
  add constraint post_comments_body_len
    check (body is null or length(body) <= 2000);
