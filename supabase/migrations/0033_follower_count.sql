-- Materialised follower count on cars.
-- A trigger keeps it in sync with the follows table so car pages can read it
-- in a single row fetch instead of doing a COUNT join on every load.

alter table public.cars
  add column if not exists follower_count integer not null default 0;

-- Back-fill from the current follows data.
update public.cars c
set follower_count = (
  select count(*) from public.follows f where f.car_id = c.id
);

-- Trigger function: increment / decrement on follow/unfollow.
create or replace function public.update_car_follower_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    update cars set follower_count = follower_count + 1 where id = NEW.car_id;
  elsif TG_OP = 'DELETE' then
    update cars set follower_count = greatest(0, follower_count - 1) where id = OLD.car_id;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_car_follower_count on public.follows;
create trigger trg_car_follower_count
  after insert or delete on public.follows
  for each row execute function public.update_car_follower_count();
