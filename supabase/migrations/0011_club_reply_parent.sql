-- Threaded club replies: a reply can be a reply to another reply.
-- parent_id null = top-level reply; otherwise points at the reply it answers.
alter table public.club_replies
  add column if not exists parent_id uuid references public.club_replies(id) on delete cascade;

create index if not exists club_replies_parent_idx on public.club_replies (parent_id);
