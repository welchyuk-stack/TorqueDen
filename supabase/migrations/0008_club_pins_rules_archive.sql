-- Club moderation 2a: pinned threads, club rules, archive, ownership transfer.

alter table public.clubs        add column if not exists rules text;
alter table public.clubs        add column if not exists is_archived boolean not null default false;
alter table public.club_threads add column if not exists is_pinned   boolean not null default false;

-- Owner can change member roles — needed for transferring ownership.
drop policy if exists "Owner manages roles" on public.club_members;
create policy "Owner manages roles" on public.club_members for update using (
  exists (select 1 from public.clubs c where c.id = club_members.club_id and c.owner_id = auth.uid())
);

-- Posting is also blocked when a club is archived (owner included). Locked
-- still lets the owner post; archived is read-only for everyone.
drop policy if exists "Members can post threads" on public.club_threads;
create policy "Members can post threads" on public.club_threads for insert with check (
  author_id = auth.uid()
  and exists (select 1 from public.club_members m where m.club_id = club_threads.club_id and m.user_id = auth.uid())
  and not exists (select 1 from public.clubs c where c.id = club_threads.club_id and c.is_archived)
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
  and not exists (
    select 1 from public.club_threads t join public.clubs c on c.id = t.club_id
    where t.id = club_replies.thread_id and c.is_archived
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
