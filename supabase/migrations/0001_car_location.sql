-- Marketplace-style location search: give each car an optional geo location.
-- latitude/longitude drive the radius filter; location_name is a human label
-- (e.g. "Manchester, UK") captured via reverse-geocoding when the car is added.
alter table public.cars
  add column if not exists latitude      double precision,
  add column if not exists longitude     double precision,
  add column if not exists location_name text;

-- Optional coarse index to help future server-side radius queries.
create index if not exists cars_lat_lng_idx on public.cars (latitude, longitude);
