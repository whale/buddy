-- Buddy sync — CAS server (replaces the interim last-write-wins buddy_push).
--
-- Architecture (LOCKED 2026-06-19, IOS-COMPANION-PLAN.md decision log): the merge
-- runs on the CLIENT (tested JS + Swift). The server is a DUMB ATOMIC STORE with a
-- monotonic version stamp. It contains NO merge logic. This function is the exact
-- server-side mirror of makeFakeCASStore() in dist/index.html — keep them in lockstep.
--
-- Contract:
--   buddy_pull(key)                     → (blob, version)        0 rows if absent (client reads as version 0)
--   buddy_push(key, blob, expected_ver) → (ok, blob, version)
--     - no row yet : expected_ver must be 0 → insert at version 1, ok=true
--     - row exists : ok=true iff expected_ver = stored.version → overwrite, version := version+1
--                    else ok=false, returns the CURRENT (blob, version) so the client re-merges + retries
--   The SERVER owns the version increment; updated_at = now() is only the "synced at" label.
--   Per-item version `v` inside the blob (not wall-clock) decides item ties in the client merge.

-- Monotonic version for compare-and-swap (existing rows start at 1).
alter table public.buddy_state add column if not exists version bigint not null default 1;

-- PULL — (blob, version) for a key, or 0 rows. Client treats "no row" as version 0.
drop function if exists public.buddy_pull(text);
create or replace function public.buddy_pull(p_key text)
returns table(blob jsonb, version bigint)
language sql
security definer
set search_path = public
as $$
  select bs.blob, bs.version from public.buddy_state bs where bs.owner_id = p_key;
$$;

-- PUSH — compare-and-swap. Replaces the interim LWW signature.
drop function if exists public.buddy_push(text, jsonb, text, timestamptz);
create or replace function public.buddy_push(p_key text, p_blob jsonb, p_expected bigint, p_device text default null)
returns table(ok boolean, blob jsonb, version bigint)
language plpgsql
security definer
set search_path = public
as $$
declare cur_version bigint;
begin
  -- Lock the row (if any) so concurrent pushes serialize on the CAS check.
  select bs.version into cur_version from public.buddy_state bs where bs.owner_id = p_key for update;

  if cur_version is null then
    -- No row yet: only a first-writer (expected = 0) may create it.
    if coalesce(p_expected, 0) <> 0 then
      return query select false, null::jsonb, 0::bigint;
      return;
    end if;
    insert into public.buddy_state(owner_id, blob, device, version, updated_at)
      values (p_key, p_blob, p_device, 1, now());
    return query select true, p_blob, 1::bigint;
    return;
  end if;

  if p_expected = cur_version then
    update public.buddy_state
      set blob = p_blob, device = p_device, version = cur_version + 1, updated_at = now()
      where owner_id = p_key;
    return query select true, p_blob, cur_version + 1;
    return;
  end if;

  -- Version mismatch → someone else wrote. Hand back the current state; client re-merges + retries.
  return query select false,
    (select bs.blob from public.buddy_state bs where bs.owner_id = p_key),
    cur_version;
end $$;

-- Lock down EXECUTE to the API roles only (RLS still denies direct table access).
revoke all on function public.buddy_pull(text) from public;
revoke all on function public.buddy_push(text, jsonb, bigint, text) from public;
grant execute on function public.buddy_pull(text) to anon, authenticated;
grant execute on function public.buddy_push(text, jsonb, bigint, text) to anon, authenticated;
