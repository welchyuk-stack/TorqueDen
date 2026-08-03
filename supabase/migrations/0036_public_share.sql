-- Public share slugs and opt-out toggle for cars.
alter table public.cars
  add column if not exists public_slug   text unique,
  add column if not exists share_enabled boolean not null default true,
  add column if not exists link_visits   integer not null default 0;

create index if not exists idx_cars_public_slug on public.cars (public_slug);

-- Anonymous visit counter — called from the public web page without auth.
create or replace function public.record_link_visit(slug text)
returns void
language sql
security definer
set search_path = public
as $$
  update public.cars
     set link_visits = link_visits + 1
   where public_slug = slug and share_enabled;
$$;

grant execute on function public.record_link_visit(text) to anon;
