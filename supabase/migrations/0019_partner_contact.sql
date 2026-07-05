-- Partner pages: add a business address and public contact email.
alter table public.partner_pages
  add column if not exists address       text,
  add column if not exists contact_email text;
