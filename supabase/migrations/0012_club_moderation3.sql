-- Club moderation batch 3: slow mode, word filter, timed mutes, mod log.

alter table public.clubs
  add column if not exists slow_mode_seconds integer not null default 0,
  add column if not exists blocked_words     text[]  not null default '{}';

-- Timed mutes (temporary posting bans).
create table if not exists public.club_mutes (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  until       timestamptz not null,
  created_at timestamptz not null default now(),
  unique (club_id, user_id)
);
create index if not exists club_mutes_club_idx on public.club_mutes (club_id);

-- Moderation audit log.
create table if not exists public.club_mod_log (
  id             uuid primary key default gen_random_uuid(),
  club_id        uuid not null references public.clubs(id) on delete cascade,
  actor_id       uuid not null default auth.uid() references public.profiles(id) on delete set null,
  action         text not null,       -- 'ban' | 'mute' | 'remove' | 'delete_thread' | ...
  target_user_id uuid,
  detail         text,
  created_at     timestamptz not null default now()
);
create index if not exists club_mod_log_club_idx on public.club_mod_log (club_id, created_at desc);

grant select, insert, delete on public.club_mutes to authenticated;
grant select, insert on public.club_mod_log to authenticated;

alter table public.club_mutes   enable row level security;
alter table public.club_mod_log enable row level security;

-- Helpers (SECURITY DEFINER so they can run inside RLS / triggers).
create or replace function public.is_muted(club uuid, usr uuid) returns boolean
  language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from club_mutes m where m.club_id = club and m.user_id = usr and m.until > now());
$$;

create or replace function public.can_post_now(club uuid) returns boolean
  language sql stable security definer set search_path to 'public' as $$
  select case
    when coalesce((select slow_mode_seconds from clubs where id = club), 0) = 0 then true
    when public.is_club_mod(club) then true
    else not exists (
      select 1 from (
        select created_at from club_threads where club_id = club and author_id = auth.uid()
        union all
        select r.created_at from club_replies r
          join club_threads t on t.id = r.thread_id
          where t.club_id = club and r.author_id = auth.uid()
      ) posts
      where posts.created_at > now() - make_interval(
        secs => (select slow_mode_seconds from clubs where id = club)))
  end;
$$;

-- Word filter: block inserts whose text contains a blocked word for the club.
create or replace function public.check_thread_words() returns trigger
  language plpgsql security definer set search_path to 'public' as $$
declare words text[]; w text; content text;
begin
  select blocked_words into words from clubs where id = NEW.club_id;
  content := lower(coalesce(NEW.title, '') || ' ' || coalesce(NEW.body, ''));
  if words is not null then
    foreach w in array words loop
      if length(trim(w)) > 0 and position(lower(trim(w)) in content) > 0 then
        raise exception 'BLOCKED_WORD';
      end if;
    end loop;
  end if;
  return NEW;
end; $$;

create or replace function public.check_reply_words() returns trigger
  language plpgsql security definer set search_path to 'public' as $$
declare words text[]; w text; content text;
begin
  select c.blocked_words into words from clubs c
    join club_threads t on t.club_id = c.id where t.id = NEW.thread_id;
  content := lower(coalesce(NEW.body, ''));
  if words is not null then
    foreach w in array words loop
      if length(trim(w)) > 0 and position(lower(trim(w)) in content) > 0 then
        raise exception 'BLOCKED_WORD';
      end if;
    end loop;
  end if;
  return NEW;
end; $$;

drop trigger if exists check_words on public.club_threads;
create trigger check_words before insert on public.club_threads
  for each row execute function public.check_thread_words();
drop trigger if exists check_words on public.club_replies;
create trigger check_words before insert on public.club_replies
  for each row execute function public.check_reply_words();

-- Mutes: mods manage; the muted user just can't post (enforced below).
create policy "Mods view mutes"   on public.club_mutes for select using (public.is_club_mod(club_id));
create policy "Mods add mutes"    on public.club_mutes for insert with check (public.is_club_mod(club_id));
create policy "Mods remove mutes" on public.club_mutes for delete using (public.is_club_mod(club_id));

-- Mod log: mods read and append.
create policy "Mods read log"  on public.club_mod_log for select using (public.is_club_mod(club_id));
create policy "Mods write log" on public.club_mod_log for insert with check (public.is_club_mod(club_id));

-- Fold mute + slow mode into the posting policies.
drop policy if exists "Members can post threads" on public.club_threads;
create policy "Members can post threads" on public.club_threads for insert with check (
  author_id = auth.uid()
  and exists (select 1 from public.club_members m where m.club_id = club_threads.club_id and m.user_id = auth.uid())
  and not public.is_banned(club_threads.club_id, auth.uid())
  and not public.is_muted(club_threads.club_id, auth.uid())
  and not exists (select 1 from public.clubs c where c.id = club_threads.club_id and c.is_archived)
  and (public.is_club_mod(club_threads.club_id)
       or not exists (select 1 from public.clubs c where c.id = club_threads.club_id and c.is_locked))
  and public.can_post_now(club_threads.club_id)
);

drop policy if exists "Members can reply" on public.club_replies;
create policy "Members can reply" on public.club_replies for insert with check (
  author_id = auth.uid()
  and exists (select 1 from public.club_members m
              join public.club_threads t on t.club_id = m.club_id
              where t.id = club_replies.thread_id and m.user_id = auth.uid())
  and not public.is_banned((select t.club_id from public.club_threads t where t.id = club_replies.thread_id), auth.uid())
  and not public.is_muted((select t.club_id from public.club_threads t where t.id = club_replies.thread_id), auth.uid())
  and not exists (select 1 from public.club_threads t join public.clubs c on c.id = t.club_id
                  where t.id = club_replies.thread_id and c.is_archived)
  and (public.is_club_mod((select t.club_id from public.club_threads t where t.id = club_replies.thread_id))
       or not exists (select 1 from public.club_threads t join public.clubs c on c.id = t.club_id
                      where t.id = club_replies.thread_id and c.is_locked))
  and public.can_post_now((select t.club_id from public.club_threads t where t.id = club_replies.thread_id))
);
