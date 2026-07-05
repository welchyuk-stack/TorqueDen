-- Push device tokens (FCM). One row per device token; a user can have several
-- (multiple devices). The send-push edge function reads these to deliver a
-- remote notification for each of a recipient's devices.

create table if not exists public.device_tokens (
  token      text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  platform   text not null default 'ios',   -- ios | android | other
  updated_at timestamptz not null default now()
);

create index if not exists device_tokens_user_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;
grant select, insert, update, delete on public.device_tokens to authenticated;

-- Each user manages only their own device tokens. The edge function reads them
-- with the service role (bypasses RLS) to send push.
create policy "Manage own device tokens" on public.device_tokens
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
