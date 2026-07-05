-- In-app notifications: a per-user feed of events, created by triggers that
-- respect each recipient's notification_prefs (migration 0015). Clients read /
-- mark-read / delete their own rows but never insert — triggers (security
-- definer) do that. Remote push is layered on separately (device_tokens + an
-- edge function) and reuses the same title/body.

create table if not exists public.notifications (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles(id) on delete cascade, -- recipient
  type           text not null,   -- new_follower|post_comment|post_like|club_new_thread|thread_reply|comment_reply
  actor_id       uuid references public.profiles(id) on delete set null,        -- who caused it
  title          text not null,
  body           text,
  -- context for deep-linking (nullable; which are set depends on type)
  car_id         uuid references public.cars(id) on delete cascade,
  build_entry_id uuid references public.build_entries(id) on delete cascade,
  club_id        uuid references public.clubs(id) on delete cascade,
  thread_id      uuid references public.club_threads(id) on delete cascade,
  read           boolean not null default false,
  created_at     timestamptz not null default now()
);

create index if not exists notifications_user_idx
  on public.notifications (user_id, created_at desc);
create index if not exists notifications_unread_idx
  on public.notifications (user_id) where not read;

alter table public.notifications enable row level security;
grant select, update, delete on public.notifications to authenticated;

create policy "Read own notifications" on public.notifications
  for select using (user_id = auth.uid());
create policy "Update own notifications" on public.notifications
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Delete own notifications" on public.notifications
  for delete using (user_id = auth.uid());

-- A person's display label for notification titles.
create or replace function public.display_label(uid uuid)
returns text language sql stable set search_path = public as $$
  select coalesce(nullif(trim(p.display_name), ''), '@' || p.username, 'Someone')
  from public.profiles p where p.id = uid;
$$;

-- Does this recipient want this preference? A missing prefs row = opt-in (true).
create or replace function public.wants_notif(uid uuid, pref text)
returns boolean language plpgsql stable set search_path = public as $$
declare v boolean;
begin
  execute format('select %I from public.notification_prefs where user_id = $1', pref)
    into v using uid;
  return coalesce(v, true);
end;
$$;

-- Central insert helper: suppresses self-notifications and honours the pref.
create or replace function public.push_notification(
  p_user uuid, p_type text, p_actor uuid, p_pref text,
  p_title text, p_body text default null,
  p_car uuid default null, p_build uuid default null,
  p_club uuid default null, p_thread uuid default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_user is null or p_user = p_actor then return; end if;
  if not public.wants_notif(p_user, p_pref) then return; end if;
  insert into public.notifications
    (user_id, type, actor_id, title, body, car_id, build_entry_id, club_id, thread_id)
  values
    (p_user, p_type, p_actor, p_title, p_body, p_car, p_build, p_club, p_thread);
end;
$$;

-- new_follower: someone follows one of your builds.
create or replace function public.notify_on_follow() returns trigger
language plpgsql security definer set search_path = public as $$
declare owner uuid; carname text;
begin
  select owner_id, coalesce(nullif(trim(nickname), ''), make || ' ' || model)
    into owner, carname
    from public.cars where id = NEW.car_id;
  perform public.push_notification(
    p_user := owner, p_type := 'new_follower', p_actor := NEW.follower_id,
    p_pref := 'new_follower',
    p_title := public.display_label(NEW.follower_id) || ' followed your build',
    p_body := carname, p_car := NEW.car_id);
  return NEW;
end;
$$;
drop trigger if exists trg_notify_on_follow on public.follows;
create trigger trg_notify_on_follow after insert on public.follows
  for each row execute function public.notify_on_follow();

-- post_like: a like on your feed post.
create or replace function public.notify_on_post_like() returns trigger
language plpgsql security definer set search_path = public as $$
declare owner uuid; ptitle text;
begin
  select c.owner_id, be.title into owner, ptitle
    from public.build_entries be join public.cars c on c.id = be.car_id
    where be.id = NEW.build_entry_id;
  perform public.push_notification(
    p_user := owner, p_type := 'post_like', p_actor := NEW.user_id,
    p_pref := 'post_likes',
    p_title := public.display_label(NEW.user_id) || ' liked your post',
    p_body := ptitle, p_build := NEW.build_entry_id);
  return NEW;
end;
$$;
drop trigger if exists trg_notify_on_post_like on public.post_likes;
create trigger trg_notify_on_post_like after insert on public.post_likes
  for each row execute function public.notify_on_post_like();

-- post_comment: a comment on your feed post (or a reply to your comment).
create or replace function public.notify_on_post_comment() returns trigger
language plpgsql security definer set search_path = public as $$
declare recip uuid;
begin
  if NEW.parent_id is null then
    select c.owner_id into recip
      from public.build_entries be join public.cars c on c.id = be.car_id
      where be.id = NEW.build_entry_id;
  else
    select user_id into recip from public.post_comments where id = NEW.parent_id;
  end if;
  perform public.push_notification(
    p_user := recip, p_type := 'post_comment', p_actor := NEW.user_id,
    p_pref := 'post_comments',
    p_title := public.display_label(NEW.user_id) ||
      (case when NEW.parent_id is null then ' commented on your post'
            else ' replied to your comment' end),
    p_body := left(NEW.body, 120), p_build := NEW.build_entry_id);
  return NEW;
end;
$$;
drop trigger if exists trg_notify_on_post_comment on public.post_comments;
create trigger trg_notify_on_post_comment after insert on public.post_comments
  for each row execute function public.notify_on_post_comment();

-- club_new_thread: a new thread in a club you're in (notify every member).
create or replace function public.notify_on_club_thread() returns trigger
language plpgsql security definer set search_path = public as $$
declare clubname text;
begin
  select name into clubname from public.clubs where id = NEW.club_id;
  insert into public.notifications
    (user_id, type, actor_id, title, body, club_id, thread_id)
  select m.user_id, 'club_new_thread', NEW.author_id,
         public.display_label(NEW.author_id) || ' posted in ' || coalesce(clubname, 'a club'),
         NEW.title, NEW.club_id, NEW.id
    from public.club_members m
   where m.club_id = NEW.club_id
     and m.user_id <> NEW.author_id
     and public.wants_notif(m.user_id, 'club_new_threads');
  return NEW;
end;
$$;
drop trigger if exists trg_notify_on_club_thread on public.club_threads;
create trigger trg_notify_on_club_thread after insert on public.club_threads
  for each row execute function public.notify_on_club_thread();

-- thread_reply / comment_reply: a reply to your thread, or to your reply.
create or replace function public.notify_on_club_reply() returns trigger
language plpgsql security definer set search_path = public as $$
declare recip uuid; clubid uuid;
begin
  select club_id into clubid from public.club_threads where id = NEW.thread_id;
  if NEW.parent_id is null then
    select author_id into recip from public.club_threads where id = NEW.thread_id;
    perform public.push_notification(
      p_user := recip, p_type := 'thread_reply', p_actor := NEW.author_id,
      p_pref := 'thread_replies',
      p_title := public.display_label(NEW.author_id) || ' replied to your thread',
      p_body := left(NEW.body, 120), p_club := clubid, p_thread := NEW.thread_id);
  else
    select author_id into recip from public.club_replies where id = NEW.parent_id;
    perform public.push_notification(
      p_user := recip, p_type := 'comment_reply', p_actor := NEW.author_id,
      p_pref := 'comment_replies',
      p_title := public.display_label(NEW.author_id) || ' replied to your comment',
      p_body := left(NEW.body, 120), p_club := clubid, p_thread := NEW.thread_id);
  end if;
  return NEW;
end;
$$;
drop trigger if exists trg_notify_on_club_reply on public.club_replies;
create trigger trg_notify_on_club_reply after insert on public.club_replies
  for each row execute function public.notify_on_club_reply();
