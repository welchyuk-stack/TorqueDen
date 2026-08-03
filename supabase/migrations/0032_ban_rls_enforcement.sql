-- Enforce is_banned at the database level on all INSERT policies.
-- Previously is_banned was set by admin but not checked by RLS — a banned
-- user could still POST if they bypassed the app. This adds a NOT EXISTS
-- check to every relevant INSERT policy so the DB itself blocks them.

-- Helper: reusable banned-check expression
-- not_banned := not exists (select 1 from public.profiles where id = auth.uid() and is_banned = true)

-- ── build_entries (feed posts) ──────────────────────────────────────────────
drop policy if exists "Users can insert own build entries" on public.build_entries;
create policy "Users can insert own build entries"
  on public.build_entries for insert
  with check (
    auth.uid() is not null
    and not exists (
      select 1 from public.profiles
      where id = auth.uid() and is_banned = true
    )
  );

-- ── post_comments ───────────────────────────────────────────────────────────
drop policy if exists "Users can insert comments" on public.post_comments;
create policy "Users can insert comments"
  on public.post_comments for insert
  with check (
    auth.uid() is not null
    and not exists (
      select 1 from public.profiles
      where id = auth.uid() and is_banned = true
    )
  );

-- ── club_threads (forum threads) ────────────────────────────────────────────
drop policy if exists "Members can insert threads" on public.club_threads;
create policy "Members can insert threads"
  on public.club_threads for insert
  with check (
    auth.uid() is not null
    and not exists (
      select 1 from public.profiles
      where id = auth.uid() and is_banned = true
    )
    and exists (
      select 1 from public.club_members
      where club_id = club_threads.club_id and user_id = auth.uid()
    )
  );

-- ── club_replies (forum replies) ────────────────────────────────────────────
drop policy if exists "Members can insert replies" on public.club_replies;
create policy "Members can insert replies"
  on public.club_replies for insert
  with check (
    auth.uid() is not null
    and not exists (
      select 1 from public.profiles
      where id = auth.uid() and is_banned = true
    )
    and exists (
      select 1 from public.club_members
      where club_id = (
        select club_id from public.club_threads where id = club_replies.thread_id
      )
      and user_id = auth.uid()
    )
  );

-- ── car_meets ───────────────────────────────────────────────────────────────
drop policy if exists "Users can insert meets" on public.car_meets;
create policy "Users can insert meets"
  on public.car_meets for insert
  with check (
    auth.uid() is not null
    and not exists (
      select 1 from public.profiles
      where id = auth.uid() and is_banned = true
    )
  );

-- ── meet_rsvps ──────────────────────────────────────────────────────────────
drop policy if exists "Users can insert rsvps" on public.meet_rsvps;
create policy "Users can insert rsvps"
  on public.meet_rsvps for insert
  with check (
    auth.uid() is not null
    and not exists (
      select 1 from public.profiles
      where id = auth.uid() and is_banned = true
    )
  );
