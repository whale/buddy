-- ============================================================================
-- Buddy sync — HOSTED SETUP (paste this whole file into the Supabase SQL editor)
-- ============================================================================
-- One-time setup for syncing to a REAL iPhone via a free hosted Supabase project.
-- Steps (see SYNC-HANDOFF.md): create a project at supabase.com → open the SQL
-- editor → paste ALL of this → Run. Then copy your Project URL + anon key into
-- Buddy's Mac Settings. Safe to run more than once (create-if-not-exists / drops).
--
-- This is the two migrations (buddy_state + the CAS upgrade) concatenated, in order.
-- ============================================================================

-- Buddy sync — one document per user, capability-scoped (no login).
--
-- The whole Buddy state ({today, history, deferred, settings}) is stored as one
-- JSONB blob keyed by a HIGH-ENTROPY sync key generated on first run and shared to
-- other devices by scanning a QR code. The key IS the capability: there is no
-- login, and the public anon key alone grants nothing.
--
-- Access is NOT via direct table reads. RLS is on with NO permissive policies, so
-- anon/authenticated cannot select/insert/update the table directly (and therefore
-- cannot ENUMERATE other users' rows). Everything goes through two SECURITY DEFINER
-- functions that only ever touch the single row whose owner_id == the supplied key.
-- Brute-forcing keys is infeasible (256-bit); still, add edge rate-limiting later.

create table if not exists public.buddy_state (
  owner_id   text primary key,            -- the sync key (capability)
  blob       jsonb       not null,        -- serialized Buddy state
  device     text,                        -- last writer label (for "synced at" / debug)
  updated_at timestamptz not null default now()
);

alter table public.buddy_state enable row level security;
-- (intentionally no policies → direct anon/authenticated access is denied)

-- PULL — return the document for a key, or nothing.
create or replace function public.buddy_pull(p_key text)
returns table(blob jsonb, device text, updated_at timestamptz)
language sql
security definer
set search_path = public
as $$
  select blob, device, updated_at
  from public.buddy_state
  where owner_id = p_key;
$$;

-- PUSH — upsert the document. LAST-WRITE-WINS by updated_at: only overwrite when the
-- incoming change is at least as new, so a stale device can't clobber a fresher one.
-- Returns the authoritative updated_at (== input if it won, else the newer existing
-- value → the caller knows its copy was stale and should pull).
create or replace function public.buddy_push(p_key text, p_blob jsonb, p_device text, p_updated_at timestamptz)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare existing timestamptz;
begin
  select updated_at into existing from public.buddy_state where owner_id = p_key;
  if existing is null or p_updated_at >= existing then
    insert into public.buddy_state(owner_id, blob, device, updated_at)
      values (p_key, p_blob, p_device, p_updated_at)
    on conflict (owner_id) do update
      set blob = excluded.blob, device = excluded.device, updated_at = excluded.updated_at;
    return p_updated_at;
  end if;
  return existing;
end;
$$;

-- Lock down EXECUTE: only the API roles, nothing implicit.
revoke all on function public.buddy_pull(text) from public;
revoke all on function public.buddy_push(text, jsonb, text, timestamptz) from public;
grant execute on function public.buddy_pull(text) to anon, authenticated;
grant execute on function public.buddy_push(text, jsonb, text, timestamptz) to anon, authenticated;

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
