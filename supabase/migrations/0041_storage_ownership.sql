-- Storage IDOR fix for the car-photos bucket.
--
-- The two existing policies gated on nothing but the bucket name:
--
--   "Authenticated can update car photos" UPDATE → (bucket_id = 'car-photos')
--   "Authenticated can upload car photos" INSERT → (bucket_id = 'car-photos')
--
-- So any signed-in user could overwrite ANY other user's car photo, avatar,
-- club banner or meet image — a textbook insecure direct object reference. The
-- database was the only thing that could have caught it; the app never sends an
-- owner alongside a storage write.
--
-- Every upload site in the app writes to '<uid>/<filename>' (verified across
-- account, add_car, create_post, create_meet, club_manage, create_club,
-- partner banner and build_tab), so the first path segment is the owner and is
-- what these policies now check.

-- ── writes must land in the caller's own folder ────────────────────────────
drop policy if exists "Authenticated can upload car photos" on storage.objects;
create policy "Authenticated can upload car photos"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'car-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Authenticated can update car photos" on storage.objects;
create policy "Authenticated can update car photos"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'car-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'car-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ── deletes: previously impossible ─────────────────────────────────────────
-- There was no DELETE policy at all, so RLS denied every delete. The app calls
-- storage.remove() when a post or its media is deleted (feed_screen.dart,
-- posts_tab.dart), meaning those files were never actually removed and have
-- been accumulating against the 1GB storage quota. Same ownership rule.
drop policy if exists "Authenticated can delete own car photos" on storage.objects;
create policy "Authenticated can delete own car photos"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'car-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
