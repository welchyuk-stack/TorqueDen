-- Thumbs up/down on club replies. One vote per user per reply (+1 or -1);
-- the score is the sum. Threads keep their date/pinned ordering — only replies
-- get votes, and reply order is unchanged (this is just a signal).

create table if not exists public.club_reply_votes (
  id         uuid primary key default gen_random_uuid(),
  reply_id   uuid not null references public.club_replies(id) on delete cascade,
  user_id    uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  value      smallint not null check (value in (-1, 1)),
  created_at timestamptz not null default now(),
  unique (reply_id, user_id)
);
create index if not exists club_reply_votes_reply_idx on public.club_reply_votes (reply_id);

grant select on public.club_reply_votes to anon, authenticated;
grant insert, update, delete on public.club_reply_votes to authenticated;

alter table public.club_reply_votes enable row level security;

-- Votes are public (so scores are visible); you manage only your own.
create policy "Votes are viewable by everyone" on public.club_reply_votes for select using (true);
create policy "Cast own vote"   on public.club_reply_votes for insert with check (user_id = auth.uid());
create policy "Change own vote" on public.club_reply_votes for update using (user_id = auth.uid());
create policy "Clear own vote"  on public.club_reply_votes for delete using (user_id = auth.uid());
