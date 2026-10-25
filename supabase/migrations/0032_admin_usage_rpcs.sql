-- RPC helpers for the admin dashboard to query project resource usage
-- without needing a Supabase Management API PAT.

create or replace function get_db_size()
returns bigint
language sql
security definer
set search_path = ''
as $$
  select pg_database_size(current_database())::bigint;
$$;

create or replace function get_storage_size()
returns bigint
language sql
security definer
set search_path = ''
as $$
  select coalesce(
    (select sum((metadata->>'size')::bigint) from storage.objects where metadata is not null),
    0
  )::bigint;
$$;
