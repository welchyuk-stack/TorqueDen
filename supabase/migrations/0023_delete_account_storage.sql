-- Harden in-app account deletion (Apple 5.1.1(v) + UK GDPR right to erasure).
--
-- 0017 created delete_own_account() but it only deleted the auth.users row
-- (which cascades to public.profiles and everything the user owns). It left the
-- user's uploaded FILES behind in the car-photos bucket. Every upload in the
-- app is stored under a "{uid}/" path prefix — avatars, car photos, post and
-- build-log media, club images/banners, partner banners — so a single prefix
-- match removes the user's entire storage footprint.
--
-- Deleting the storage.objects rows makes the files immediately inaccessible
-- (their public URLs 404). Reclaiming the physical blobs, if ever needed, can
-- be done later with an edge function using the Storage API.
--
-- CREATE OR REPLACE, so this is safe to apply whether or not 0017 already ran.
create or replace function public.delete_own_account() returns void
  language plpgsql security definer
  set search_path to 'public', 'auth', 'storage'
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  -- 1. Remove the user's uploaded files (everything under car-photos/{uid}/).
  --    Best-effort: file cleanup must never block the account deletion itself
  --    (the Apple 5.1.1(v) requirement), so swallow any error here.
  begin
    delete from storage.objects
      where bucket_id = 'car-photos'
        and (storage.foldername(name))[1] = v_uid::text;
  exception when others then
    null;
  end;

  -- 2. Delete the auth user; cascades to public.profiles and from there to the
  --    user's cars, build entries, posts, clubs, memberships and comments.
  delete from auth.users where id = v_uid;
end;
$$;

grant execute on function public.delete_own_account() to authenticated;
