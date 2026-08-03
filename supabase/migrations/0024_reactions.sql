-- Add reaction_type to post_likes so users can react with more than just fire.
-- Existing rows keep 'fire' as the default; the unique constraint is updated
-- to allow one of each reaction type per user per post.

alter table public.post_likes
  add column if not exists reaction_type text not null default 'fire'
    check (reaction_type in ('fire', 'clean', 'sick', 'insane'));

-- Drop the old unique constraint (build_entry_id, user_id) and replace it
-- with one that allows one of *each* type per user per post.
alter table public.post_likes
  drop constraint if exists post_likes_build_entry_id_user_id_key;

alter table public.post_likes
  add constraint post_likes_build_entry_id_user_id_type_key
    unique (build_entry_id, user_id, reaction_type);

-- Index so the per-post reaction count query stays fast.
create index if not exists idx_post_likes_entry_type
  on public.post_likes (build_entry_id, reaction_type);
