-- Moderation, batch 1: reporting content/users and blocking users.
-- (App Store requires both for user-generated content.)

create table if not exists public.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  target_type text not null,  -- 'post' | 'comment' | 'thread' | 'reply' | 'club' | 'user'
  target_id   uuid not null,
  reason      text not null,
  note        text,
  status      text not null default 'open',  -- 'open' | 'reviewed'
  created_at  timestamptz not null default now()
);

create table if not exists public.blocks (
  id         uuid primary key default gen_random_uuid(),
  blocker_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (blocker_id, blocked_id)
);

create index if not exists blocks_blocker_idx on public.blocks (blocker_id);

grant select, insert on public.reports to authenticated;
grant select, insert, delete on public.blocks to authenticated;

alter table public.reports enable row level security;
alter table public.blocks  enable row level security;

-- Reports: you can file them and see your own (review tooling comes later).
create policy "File a report" on public.reports for insert with check (reporter_id = auth.uid());
create policy "See own reports" on public.reports for select using (reporter_id = auth.uid());

-- Blocks: fully private to the blocker.
create policy "Manage own blocks (select)" on public.blocks for select using (blocker_id = auth.uid());
create policy "Manage own blocks (insert)" on public.blocks for insert with check (blocker_id = auth.uid());
create policy "Manage own blocks (delete)" on public.blocks for delete using (blocker_id = auth.uid());
