-- Let a post (build entry) optionally link to a mod in the same car's build
-- list. Mods are build entries with a category, so this is a self-reference:
-- the post points at the mod's build_entries row.
--
-- ON DELETE SET NULL: if the linked mod is removed, the post simply loses its
-- link rather than being deleted.
alter table public.build_entries
  add column if not exists linked_build_entry_id uuid
    references public.build_entries(id) on delete set null;
