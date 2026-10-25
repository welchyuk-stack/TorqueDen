-- Direct messages: 1-to-1 threaded conversations.
-- Reuses the push_notification() helper and notification_prefs pattern from 0021/0015.

-- ── Tables ──────────────────────────────────────────────────────────────────

create table if not exists public.dm_threads (
  id             uuid primary key default gen_random_uuid(),
  -- Participants stored with participant_a < participant_b so the pair can be
  -- uniquely constrained without needing a separate join table.
  participant_a  uuid not null references public.profiles(id) on delete cascade,
  participant_b  uuid not null references public.profiles(id) on delete cascade,
  last_message_at timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  constraint dm_threads_participants_check check (participant_a < participant_b),
  constraint dm_threads_pair_unique unique (participant_a, participant_b)
);

create index if not exists dm_threads_a_idx on public.dm_threads (participant_a, last_message_at desc);
create index if not exists dm_threads_b_idx on public.dm_threads (participant_b, last_message_at desc);

create table if not exists public.dm_messages (
  id         uuid primary key default gen_random_uuid(),
  thread_id  uuid not null references public.dm_threads(id) on delete cascade,
  sender_id  uuid not null references public.profiles(id) on delete cascade,
  body       text not null check (length(trim(body)) > 0),
  read_at    timestamptz,   -- null = unread for the recipient
  created_at timestamptz not null default now()
);

create index if not exists dm_messages_thread_idx on public.dm_messages (thread_id, created_at);

-- ── RLS ─────────────────────────────────────────────────────────────────────

alter table public.dm_threads  enable row level security;
alter table public.dm_messages enable row level security;

grant select, insert                        on public.dm_threads  to authenticated;
grant select, insert, update                on public.dm_messages to authenticated;

-- Helper: is the calling user a participant in this thread?
create or replace function public.is_dm_participant(thread uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.dm_threads t
    where t.id = thread
      and (t.participant_a = auth.uid() or t.participant_b = auth.uid())
  );
$$;

-- Thread policies: users can see and create threads they are part of.
-- Block check on insert: if either party blocks the other, deny the thread.
create policy "See own threads" on public.dm_threads
  for select using (
    participant_a = auth.uid() or participant_b = auth.uid()
  );

create policy "Create thread" on public.dm_threads
  for insert with check (
    -- calling user must be one of the participants
    (participant_a = auth.uid() or participant_b = auth.uid())
    -- neither party must have blocked the other
    and not exists (
      select 1 from public.blocks
       where (blocker_id = participant_a and blocked_id = participant_b)
          or (blocker_id = participant_b and blocked_id = participant_a)
    )
  );

-- Message policies: see / send messages only in your own threads.
create policy "See messages in own threads" on public.dm_messages
  for select using (public.is_dm_participant(thread_id));

create policy "Send message in own thread" on public.dm_messages
  for insert with check (
    sender_id = auth.uid()
    and public.is_dm_participant(thread_id)
    -- Can't message someone who has blocked you (or whom you've blocked).
    and not exists (
      select 1 from public.dm_threads t
      join public.blocks b on (
        (b.blocker_id = t.participant_a and b.blocked_id = t.participant_b) or
        (b.blocker_id = t.participant_b and b.blocked_id = t.participant_a)
      )
      where t.id = thread_id
    )
  );

-- Recipients can mark their messages read.
create policy "Mark messages read" on public.dm_messages
  for update using (
    public.is_dm_participant(thread_id) and sender_id <> auth.uid()
  ) with check (
    public.is_dm_participant(thread_id)
  );

-- ── Keep last_message_at current ─────────────────────────────────────────────

create or replace function public.dm_update_thread_ts()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.dm_threads set last_message_at = NEW.created_at where id = NEW.thread_id;
  return NEW;
end;
$$;

drop trigger if exists trg_dm_update_thread_ts on public.dm_messages;
create trigger trg_dm_update_thread_ts
  after insert on public.dm_messages
  for each row execute function public.dm_update_thread_ts();

-- ── Notification pref column ──────────────────────────────────────────────────

alter table public.notification_prefs
  add column if not exists direct_messages boolean not null default true;

-- ── Push notification on new message ─────────────────────────────────────────

create or replace function public.notify_on_dm()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  recip uuid;
begin
  -- Recipient is whichever participant is not the sender.
  select case
    when t.participant_a = NEW.sender_id then t.participant_b
    else t.participant_a
  end into recip
  from public.dm_threads t where t.id = NEW.thread_id;

  perform public.push_notification(
    p_user  := recip,
    p_type  := 'new_message',
    p_actor := NEW.sender_id,
    p_pref  := 'direct_messages',
    p_title := public.display_label(NEW.sender_id) || ' sent you a message',
    p_body  := left(NEW.body, 120)
  );
  return NEW;
end;
$$;

drop trigger if exists trg_notify_on_dm on public.dm_messages;
create trigger trg_notify_on_dm
  after insert on public.dm_messages
  for each row execute function public.notify_on_dm();
