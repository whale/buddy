-- buddy_pull also returns the plaintext stats column (counts, never content).
--
-- E2E encryption (0.4.0) blinded sync:doctor — it used to count items by reading
-- the blob, which is now ciphertext BY DESIGN. The clients publish integers-only
-- stats beside the ciphertext; returning them from buddy_pull lets the doctor
-- (and future support tooling) see {active, done, deferred, historyDays} without
-- anyone being able to read a single task. Old clients ignore the extra field
-- (both parse rows by named key: blob / version).

drop function if exists public.buddy_pull(text);
create or replace function public.buddy_pull(p_key text)
returns table(blob jsonb, version bigint, stats jsonb)
language sql
security definer
set search_path = public
as $$
  select bs.blob, bs.version, bs.stats from public.buddy_state bs where bs.owner_id = p_key;
$$;

revoke all on function public.buddy_pull(text) from public;
grant execute on function public.buddy_pull(text) to anon, authenticated;
