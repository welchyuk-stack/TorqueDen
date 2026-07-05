-- Club admin tools: lockable clubs + owner can remove members.

alter table public.clubs
  add column if not exists is_locked boolean not null default false;

-- Owner can remove members (not just self-leave).
drop policy if exists "Users can leave clubs" on public.club_members;
drop policy if exists "Leave or owner can remove" on public.club_members;
create policy "Leave or owner can remove" on public.club_members for delete using (
  user_id = auth.uid()
  or exists (select 1 from public.clubs c where c.id = club_members.club_id and c.owner_id = auth.uid())
);

-- Posting is blocked when a club is locked — unless you're the owner.
drop policy if exists "Members can post threads" on public.club_threads;
create policy "Members can post threads" on public.club_threads for insert with check (
  author_id = auth.uid()
  and exists (select 1 from public.club_members m where m.club_id = club_threads.club_id and m.user_id = auth.uid())
  and (
    exists (select 1 from public.clubs c where c.id = club_threads.club_id and c.owner_id = auth.uid())
    or not exists (select 1 from public.clubs c where c.id = club_threads.club_id and c.is_locked)
  )
);

drop policy if exists "Members can reply" on public.club_replies;
create policy "Members can reply" on public.club_replies for insert with check (
  author_id = auth.uid()
  and exists (
    select 1 from public.club_members m
    join public.club_threads t on t.club_id = m.club_id
    where t.id = club_replies.thread_id and m.user_id = auth.uid()
  )
  and (
    exists (
      select 1 from public.club_threads t join public.clubs c on c.id = t.club_id
      where t.id = club_replies.thread_id and c.owner_id = auth.uid()
    )
    or not exists (
      select 1 from public.club_threads t join public.clubs c on c.id = t.club_id
      where t.id = club_replies.thread_id and c.is_locked
    )
  )
);
