-- Two-strike moderation system.
-- strike_count tracks how many warnings a user has received.
-- On 1st strike a warning notification is sent; on 2nd the admin bans manually.
alter table public.profiles
  add column if not exists strike_count integer not null default 0;
