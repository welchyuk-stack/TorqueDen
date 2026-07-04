-- Privacy: coarsen existing car coordinates to a ~1 km grid (2 decimal places)
-- so an exact home/car location can't be pinpointed via the public API.
-- New/edited cars are fuzzed client-side before saving (LocationService.fuzz);
-- this back-fills rows stored before that was in place.
update public.cars
set latitude  = round(latitude::numeric, 2),
    longitude = round(longitude::numeric, 2)
where latitude is not null
  and (latitude <> round(latitude::numeric, 2)
    or longitude <> round(longitude::numeric, 2));
