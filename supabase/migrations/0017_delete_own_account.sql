-- In-app account deletion (Apple 5.1.1(v) + Google Play Data Safety require it).
-- A user can delete their own account and all associated data. Deleting the
-- auth.users row cascades to public.profiles (FK ON DELETE CASCADE) and from
-- there to cars, posts, clubs, memberships, etc. — so everything the user owns
-- goes with it.
--
-- SECURITY DEFINER so the function (owned by a privileged role) can delete from
-- the auth schema on the caller's behalf; it only ever targets auth.uid(), so a
-- user can only delete themselves.
create or replace function public.delete_own_account() returns void
  language plpgsql security definer set search_path to 'public', 'auth' as $$
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  delete from auth.users where id = auth.uid();
end; $$;

grant execute on function public.delete_own_account() to authenticated;
