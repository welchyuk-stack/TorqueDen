-- Security hardening for the ban system and build_entries writes.
--
-- Two confirmed holes, both found by reading live pg_policies:
--
--  1. profiles UPDATE was "(auth.uid() = id)" with no column restriction, so
--     a banned user could clear their own is_banned flag with a single direct
--     API call. The same policy also meant the admin ban button could never
--     work — updating *another* user's row fails auth.uid() = id, so the app
--     was reporting success while the DB did nothing.
--
--  2. "Users can insert own build entries" is PERMISSIVE and never checked
--     ownership. Permissive policies OR together, so it defeated the stricter
--     "owner writes build_entries" policy: any signed-in user could post onto
--     anybody else's car.

-- ── 1a. Platform admin flag ────────────────────────────────────────────────
-- Replaces the hardcoded UID that previously lived only in the Flutter client.
alter table public.profiles
  add column if not exists is_platform_admin boolean not null default false;

update public.profiles
  set is_platform_admin = true
  where id = '807e6e7c-ebe7-49d3-b774-ad9a75be86f9';

-- ── 1b. Stop clients writing moderation columns ────────────────────────────
-- RLS alone can't express "you may update this row but not these columns", so
-- use column-level privileges.
--
-- A bare "revoke update (cols)" does NOT work here and fails silently: Supabase
-- grants authenticated/anon UPDATE at the *table* level, and a table-level
-- grant implicitly covers every column. Postgres accepts the column revoke and
-- changes nothing. The table grant has to be dropped first, then re-granted
-- column by column.
--
-- The list is derived from the catalogue rather than written out, so columns
-- added later are writable by default and only these three stay protected.
-- anon is deliberately not re-granted: it can never satisfy the
-- "auth.uid() = id" row policy anyway.
do $$
declare cols text;
begin
  select string_agg(quote_ident(column_name), ', ')
    into cols
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'profiles'
     and column_name not in ('is_banned', 'strike_count', 'is_platform_admin');

  execute 'revoke update on public.profiles from authenticated, anon';
  execute format('grant update (%s) on public.profiles to authenticated', cols);
end $$;

-- ── 1c. Admin ban/unban via a definer function ─────────────────────────────
-- SECURITY DEFINER runs as the owner, so it can write the columns revoked
-- above — but only after verifying the caller is a platform admin.
create or replace function public.set_user_banned(
  target_user_id uuid,
  banned boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and is_platform_admin = true
  ) then
    raise exception 'not authorised';
  end if;

  -- An admin demoting themselves would lock the platform out of moderation.
  if target_user_id = auth.uid() then
    raise exception 'cannot ban yourself';
  end if;

  update public.profiles
    set is_banned = banned
    where id = target_user_id;
end;
$$;

revoke all on function public.set_user_banned(uuid, boolean) from public, anon;
grant execute on function public.set_user_banned(uuid, boolean) to authenticated;

-- ── 2. build_entries: require ownership on insert ──────────────────────────
-- Drop the permissive policy that skipped the ownership test. Inserts now fall
-- through to "owner writes build_entries", which does check cars.owner_id.
drop policy if exists "Users can insert own build entries" on public.build_entries;

-- Re-apply the ban gate as RESTRICTIVE so it ANDs with the ownership policy
-- instead of ORing past it — the mistake that caused this bug in the first
-- place.
drop policy if exists "banned users cannot write build entries" on public.build_entries;
create policy "banned users cannot write build entries"
  on public.build_entries
  as restrictive
  for insert
  to authenticated
  with check (
    not exists (
      select 1 from public.profiles
      where id = auth.uid() and is_banned = true
    )
  );
