-- Per-user notification preferences. One row per user; each column is an
-- opt-in toggle. Stored server-side so a future push/notification delivery
-- layer can read them. (Delivery itself is not built yet — these are prefs.)

create table if not exists public.notification_prefs (
  user_id          uuid primary key default auth.uid() references public.profiles(id) on delete cascade,
  new_follower     boolean not null default true,  -- someone follows one of your builds
  post_comments    boolean not null default true,  -- comments on your feed posts
  post_likes       boolean not null default true,  -- likes on your feed posts
  club_new_threads boolean not null default true,  -- new threads in clubs you're in
  thread_replies   boolean not null default true,  -- replies to threads you started
  comment_replies  boolean not null default true,  -- replies to your thread comments
  updated_at       timestamptz not null default now()
);

grant select, insert, update on public.notification_prefs to authenticated;
alter table public.notification_prefs enable row level security;

-- Each user reads and writes only their own row.
create policy "Own notif prefs read"   on public.notification_prefs for select using (user_id = auth.uid());
create policy "Own notif prefs insert" on public.notification_prefs for insert with check (user_id = auth.uid());
create policy "Own notif prefs update" on public.notification_prefs for update using (user_id = auth.uid());
