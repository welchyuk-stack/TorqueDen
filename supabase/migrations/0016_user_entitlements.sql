-- Per-user entitlement / membership tier. Server-authoritative: clients may
-- READ their own tier but can never write it — only the service role (a future
-- in-app-purchase validation webhook) sets it. A user with no row is 'free'.

create table if not exists public.user_entitlements (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  tier       text not null default 'free',  -- 'free' | 'premium' | 'partner'
  updated_at timestamptz not null default now()
);

-- Read-only for authenticated users. Note: NO insert/update/delete grant and
-- NO write policy — so clients cannot escalate their own tier. Grants/writes
-- happen via the service role (bypasses RLS), e.g. a purchase webhook or a
-- manual admin update.
grant select on public.user_entitlements to authenticated;
alter table public.user_entitlements enable row level security;

create policy "Read own entitlement" on public.user_entitlements for select using (user_id = auth.uid());

-- To grant Premium/Partner manually (service role / SQL editor):
--   insert into public.user_entitlements (user_id, tier)
--   values ('<uuid>', 'premium')
--   on conflict (user_id) do update set tier = excluded.tier, updated_at = now();
