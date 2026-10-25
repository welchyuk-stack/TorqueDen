-- One vote per user per challenge (switching vote moves it to the new entry)
create table challenge_votes (
  user_id    uuid references auth.users(id) on delete cascade not null,
  challenge_id uuid references challenges(id) on delete cascade not null,
  entry_id   uuid references build_entries(id) on delete cascade not null,
  created_at timestamptz default now(),
  primary key (user_id, challenge_id)
);

alter table challenge_votes enable row level security;

-- Anyone can read vote counts
create policy "challenge_votes_read" on challenge_votes
  for select using (true);

-- Authenticated users can upsert their own vote
create policy "challenge_votes_insert" on challenge_votes
  for insert with check (auth.uid() = user_id);

create policy "challenge_votes_update" on challenge_votes
  for update using (auth.uid() = user_id);

create policy "challenge_votes_delete" on challenge_votes
  for delete using (auth.uid() = user_id);

-- Fast lookup by challenge + entry for vote counts
create index challenge_votes_entry_idx on challenge_votes(challenge_id, entry_id);
