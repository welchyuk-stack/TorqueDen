-- Partner pages: a dedicated public profile for a business/brand/seller on the
-- Partner tier (banner, bio, website link). Viewable by everyone (free +
-- premium), but only a Partner-tier user can create/edit their own — enforced
-- server-side against user_entitlements so it can't be faked by the client.

create table if not exists public.partner_pages (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  business_name text not null,
  bio           text,
  banner_url    text,
  website_url   text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (owner_id) -- one page per partner
);
create index if not exists partner_pages_created_idx on public.partner_pages (created_at desc);

grant select on public.partner_pages to anon, authenticated;
grant insert, update, delete on public.partner_pages to authenticated;
alter table public.partner_pages enable row level security;

-- Is the current user on the Partner tier?
create or replace function public.is_partner() returns boolean
  language sql stable security definer set search_path to 'public' as $$
  select exists (
    select 1 from user_entitlements e
    where e.user_id = auth.uid() and e.tier = 'partner'
  );
$$;

-- Public read.
create policy "Partner pages viewable by everyone" on public.partner_pages
  for select using (true);
-- Only a Partner can create their own page.
create policy "Partners create their own page" on public.partner_pages
  for insert with check (owner_id = auth.uid() and public.is_partner());
-- Only the owner (still a Partner) can edit; owner can always delete.
create policy "Owner partner updates page" on public.partner_pages
  for update using (owner_id = auth.uid() and public.is_partner());
create policy "Owner deletes their page" on public.partner_pages
  for delete using (owner_id = auth.uid());
