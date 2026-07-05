-- Clubs: user-created communities with a discussion forum (MVP).
-- Public clubs, membership-gated posting, creator-only moderation, freeform.

-- ── Tables ──────────────────────────────────────────────────────────────────
create table if not exists public.clubs (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  description text,
  avatar_url  text,
  owner_id    uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  is_public   boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.club_members (
  id        uuid primary key default gen_random_uuid(),
  club_id   uuid not null references public.clubs(id) on delete cascade,
  user_id   uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  role      text not null default 'member', -- 'owner' | 'member'
  joined_at timestamptz not null default now(),
  unique (club_id, user_id)
);

create table if not exists public.club_threads (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs(id) on delete cascade,
  author_id  uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  title      text not null,
  body       text,
  created_at timestamptz not null default now()
);

create table if not exists public.club_replies (
  id         uuid primary key default gen_random_uuid(),
  thread_id  uuid not null references public.club_threads(id) on delete cascade,
  author_id  uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  body       text not null,
  created_at timestamptz not null default now()
);

create index if not exists club_members_club_idx  on public.club_members (club_id);
create index if not exists club_members_user_idx  on public.club_members (user_id);
create index if not exists club_threads_club_idx   on public.club_threads (club_id, created_at desc);
create index if not exists club_replies_thread_idx on public.club_replies (thread_id, created_at);

-- ── Owner auto-membership ────────────────────────────────────────────────────
create or replace function public.handle_new_club() returns trigger
  language plpgsql security definer set search_path to 'public' as $$
begin
  insert into public.club_members (club_id, user_id, role)
  values (new.id, new.owner_id, 'owner')
  on conflict (club_id, user_id) do nothing;
  return new;
end; $$;

drop trigger if exists on_club_created on public.clubs;
create trigger on_club_created after insert on public.clubs
  for each row execute function public.handle_new_club();

-- ── Grants (RLS still governs row access) ────────────────────────────────────
grant select on public.clubs, public.club_members, public.club_threads, public.club_replies to anon, authenticated;
grant insert, update, delete on public.clubs, public.club_members, public.club_threads, public.club_replies to authenticated;

-- ── Row-level security ───────────────────────────────────────────────────────
alter table public.clubs         enable row level security;
alter table public.club_members  enable row level security;
alter table public.club_threads  enable row level security;
alter table public.club_replies  enable row level security;

-- Clubs: public read; owner creates/edits/deletes.
create policy "Clubs are viewable by everyone" on public.clubs for select using (true);
create policy "Users can create clubs" on public.clubs for insert with check (owner_id = auth.uid());
create policy "Owners can update their club" on public.clubs for update using (owner_id = auth.uid());
create policy "Owners can delete their club" on public.clubs for delete using (owner_id = auth.uid());

-- Members: public read; join/leave your own membership.
create policy "Members are viewable by everyone" on public.club_members for select using (true);
create policy "Users can join clubs" on public.club_members for insert with check (user_id = auth.uid());
create policy "Users can leave clubs" on public.club_members for delete using (user_id = auth.uid());

-- Threads: public read; members post; author or club owner edits/deletes.
create policy "Threads are viewable by everyone" on public.club_threads for select using (true);
create policy "Members can post threads" on public.club_threads for insert with check (
  author_id = auth.uid()
  and exists (select 1 from public.club_members m where m.club_id = club_threads.club_id and m.user_id = auth.uid())
);
create policy "Author or owner can update thread" on public.club_threads for update using (
  author_id = auth.uid()
  or exists (select 1 from public.clubs c where c.id = club_threads.club_id and c.owner_id = auth.uid())
);
create policy "Author or owner can delete thread" on public.club_threads for delete using (
  author_id = auth.uid()
  or exists (select 1 from public.clubs c where c.id = club_threads.club_id and c.owner_id = auth.uid())
);

-- Replies: public read; members reply; author or club owner edits/deletes.
create policy "Replies are viewable by everyone" on public.club_replies for select using (true);
create policy "Members can reply" on public.club_replies for insert with check (
  author_id = auth.uid()
  and exists (
    select 1 from public.club_members m
    join public.club_threads t on t.club_id = m.club_id
    where t.id = club_replies.thread_id and m.user_id = auth.uid()
  )
);
create policy "Author or owner can update reply" on public.club_replies for update using (
  author_id = auth.uid()
  or exists (
    select 1 from public.club_threads t join public.clubs c on c.id = t.club_id
    where t.id = club_replies.thread_id and c.owner_id = auth.uid()
  )
);
create policy "Author or owner can delete reply" on public.club_replies for delete using (
  author_id = auth.uid()
  or exists (
    select 1 from public.club_threads t join public.clubs c on c.id = t.club_id
    where t.id = club_replies.thread_id and c.owner_id = auth.uid()
  )
);
