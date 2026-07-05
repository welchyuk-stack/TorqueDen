-- Club moderation 2b: admins/mods + member bans.

create table if not exists public.club_bans (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (club_id, user_id)
);
create index if not exists club_bans_club_idx on public.club_bans (club_id);

grant select, insert, delete on public.club_bans to authenticated;
alter table public.club_bans enable row level security;

-- Helpers. SECURITY DEFINER so they can be used inside RLS without tripping
-- row security / recursion on the tables they read.
create or replace function public.is_club_mod(club uuid) returns boolean
  language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from clubs c where c.id = club and c.owner_id = auth.uid())
      or exists (select 1 from club_members m
                 where m.club_id = club and m.user_id = auth.uid() and m.role in ('owner','admin'));
$$;

create or replace function public.is_banned(club uuid, usr uuid) returns boolean
  language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from club_bans b where b.club_id = club and b.user_id = usr);
$$;

-- Bans: only mods (owner/admins) see and manage them.
create policy "Mods view bans"   on public.club_bans for select using (public.is_club_mod(club_id));
create policy "Mods add bans"    on public.club_bans for insert with check (public.is_club_mod(club_id));
create policy "Mods remove bans" on public.club_bans for delete using (public.is_club_mod(club_id));

-- Threads: mods (not just the owner) can moderate; banned users can't post.
drop policy if exists "Author or owner can update thread" on public.club_threads;
create policy "Author or mod can update thread" on public.club_threads for update using (
  author_id = auth.uid() or public.is_club_mod(club_id)
);
drop policy if exists "Author or owner can delete thread" on public.club_threads;
create policy "Author or mod can delete thread" on public.club_threads for delete using (
  author_id = auth.uid() or public.is_club_mod(club_id)
);
drop policy if exists "Members can post threads" on public.club_threads;
create policy "Members can post threads" on public.club_threads for insert with check (
  author_id = auth.uid()
  and exists (select 1 from public.club_members m where m.club_id = club_threads.club_id and m.user_id = auth.uid())
  and not public.is_banned(club_threads.club_id, auth.uid())
  and not exists (select 1 from public.clubs c where c.id = club_threads.club_id and c.is_archived)
  and (public.is_club_mod(club_threads.club_id)
       or not exists (select 1 from public.clubs c where c.id = club_threads.club_id and c.is_locked))
);

-- Replies: same, resolving the club via the thread.
drop policy if exists "Author or owner can update reply" on public.club_replies;
create policy "Author or mod can update reply" on public.club_replies for update using (
  author_id = auth.uid()
  or public.is_club_mod((select t.club_id from public.club_threads t where t.id = club_replies.thread_id))
);
drop policy if exists "Author or owner can delete reply" on public.club_replies;
create policy "Author or mod can delete reply" on public.club_replies for delete using (
  author_id = auth.uid()
  or public.is_club_mod((select t.club_id from public.club_threads t where t.id = club_replies.thread_id))
);
drop policy if exists "Members can reply" on public.club_replies;
create policy "Members can reply" on public.club_replies for insert with check (
  author_id = auth.uid()
  and exists (select 1 from public.club_members m
              join public.club_threads t on t.club_id = m.club_id
              where t.id = club_replies.thread_id and m.user_id = auth.uid())
  and not public.is_banned(
        (select t.club_id from public.club_threads t where t.id = club_replies.thread_id), auth.uid())
  and not exists (select 1 from public.club_threads t join public.clubs c on c.id = t.club_id
                  where t.id = club_replies.thread_id and c.is_archived)
  and (public.is_club_mod((select t.club_id from public.club_threads t where t.id = club_replies.thread_id))
       or not exists (select 1 from public.club_threads t join public.clubs c on c.id = t.club_id
                      where t.id = club_replies.thread_id and c.is_locked))
);

-- Members: mods can remove; joining is blocked for banned users.
drop policy if exists "Leave or owner can remove" on public.club_members;
create policy "Leave or mod can remove" on public.club_members for delete using (
  user_id = auth.uid() or public.is_club_mod(club_id)
);
drop policy if exists "Users can join clubs" on public.club_members;
create policy "Users can join clubs" on public.club_members for insert with check (
  user_id = auth.uid() and not public.is_banned(club_id, auth.uid())
);
