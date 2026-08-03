-- Allow participants to delete their own DM threads.
grant delete on public.dm_threads to authenticated;

create policy "Delete own thread" on public.dm_threads
  for delete using (
    participant_a = auth.uid() or participant_b = auth.uid()
  );
