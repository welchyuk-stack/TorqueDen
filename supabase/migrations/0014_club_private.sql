-- Club moderation batch 4: private clubs with a request-to-join queue.
--
-- Private clubs stay *discoverable* — the club row, banner and member count are
-- still visible in Discover/search — but their threads and replies are hidden
-- from non-members ("restricted" style). Joining is gated: instead of a direct
-- membership insert, a user files a join request that a mod approves or denies.

alter table public.clubs
  add column if not exists is_private boolean not null default false;

-- ── Join requests ────────────────────────────────────────────────────────────
create table if not exists public.club_join_requests (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs(id) on delete cascade,
  user_id    uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (club_id, user_id)
);
create index if not exists club_join_requests_club_idx on public.club_join_requests (club_id, created_at);

grant select, insert, delete on public.club_join_requests to authenticated;
alter table public.club_join_requests enable row level security;

-- ── Helper: am I a member of this club? ──────────────────────────────────────
-- SECURITY DEFINER so it can be used inside RLS without tripping row security
-- (or recursing) on club_members.
create or replace function public.is_club_member(club uuid) returns boolean
  language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from club_members m where m.club_id = club and m.user_id = auth.uid());
$$;

-- ── Approve a join request (mods only) ───────────────────────────────────────
-- Runs as definer so a mod can create a membership row for *another* user
-- (the club_members insert policy otherwise only allows self-joins).
create or replace function public.approve_join_request(req uuid) returns void
  language plpgsql security definer set search_path to 'public' as $$
declare r record;
begin
  select * into r from club_join_requests where id = req;
  if r is null then raise exception 'REQUEST_NOT_FOUND'; end if;
  if not public.is_club_mod(r.club_id) then raise exception 'NOT_AUTHORIZED'; end if;
  if public.is_banned(r.club_id, r.user_id) then raise exception 'USER_BANNED'; end if;
  insert into public.club_members (club_id, user_id, role)
    values (r.club_id, r.user_id, 'member')
    on conflict (club_id, user_id) do nothing;
  delete from public.club_join_requests where id = req;
end; $$;

grant execute on function public.approve_join_request(uuid) to authenticated;

-- ── Restricted visibility: hide private-club content from non-members ────────
drop policy if exists "Threads are viewable by everyone" on public.club_threads;
create policy "Threads viewable (public or member)" on public.club_threads for select using (
  not exists (select 1 from public.clubs c where c.id = club_threads.club_id and c.is_private)
  or public.is_club_member(club_threads.club_id)
);

drop policy if exists "Replies are viewable by everyone" on public.club_replies;
create policy "Replies viewable (public or member)" on public.club_replies for select using (
  not exists (
    select 1 from public.clubs c
      join public.club_threads t on t.club_id = c.id
      where t.id = club_replies.thread_id and c.is_private)
  or public.is_club_member(
       (select t.club_id from public.club_threads t where t.id = club_replies.thread_id))
);

-- ── Join gating: no direct self-join on private clubs ────────────────────────
-- Public clubs stay open; private-club membership only arrives via
-- approve_join_request(). Owner auto-membership (handle_new_club trigger) is a
-- definer insert and is unaffected.
drop policy if exists "Users can join clubs" on public.club_members;
create policy "Users can join clubs" on public.club_members for insert with check (
  user_id = auth.uid()
  and not public.is_banned(club_id, auth.uid())
  and not exists (select 1 from public.clubs c where c.id = club_id and c.is_private)
);

-- ── Request table policies ───────────────────────────────────────────────────
-- Requester sees their own request; mods see the whole queue.
create policy "See own or mod sees all requests" on public.club_join_requests for select using (
  user_id = auth.uid() or public.is_club_mod(club_id)
);
-- Only for private clubs, only yourself, not if banned or already a member.
create policy "Request to join a private club" on public.club_join_requests for insert with check (
  user_id = auth.uid()
  and exists (select 1 from public.clubs c where c.id = club_id and c.is_private)
  and not public.is_banned(club_id, auth.uid())
  and not public.is_club_member(club_id)
);
-- Requester can cancel; a mod can deny.
create policy "Cancel own or mod denies request" on public.club_join_requests for delete using (
  user_id = auth.uid() or public.is_club_mod(club_id)
);
