-- Restrict what can be uploaded to the storage buckets.
--
-- Both buckets were public with NO file_size_limit and NO allowed_mime_types,
-- so any authenticated user could store a file of any type and any size.
--
-- Two consequences, both reachable by calling the storage REST API directly
-- (the app's own contentType is set from the file extension, but nothing
-- forces a caller to use the app):
--
--   1. Uploading text/html returned a URL on the public Supabase CDN that
--      renders as a web page — a phishing or stored-XSS page hosted from the
--      domain the app's own images come from.
--   2. No size ceiling on a 1GB / 5GB-egress free tier: a single caller could
--      exhaust the project quota in minutes.
--
-- MIME type and size are enforced by storage itself on upload, which is the
-- only layer an attacker bypassing the app still has to go through.

-- car-photos: user photos and (when Features.video is on) short clips.
update storage.buckets
   set file_size_limit = 26214400, -- 25 MB
       allowed_mime_types = array[
         'image/jpeg','image/png','image/webp','image/gif','image/heic',
         'video/mp4','video/quicktime'
       ]
 where id = 'car-photos';

-- share-cards: generated PNG share images only.
update storage.buckets
   set file_size_limit = 5242880, -- 5 MB
       allowed_mime_types = array['image/png','image/jpeg']
 where id = 'share-cards';
