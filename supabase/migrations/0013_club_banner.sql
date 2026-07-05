-- A wide banner image for the club header (separate from the square icon shown
-- in lists). Set on creation and editable in Manage.
alter table public.clubs
  add column if not exists banner_url text;
