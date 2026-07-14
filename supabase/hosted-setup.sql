-- ============================================================================
-- Buddy sync — HOSTED SETUP (paste this whole file into the Supabase SQL editor)
-- ============================================================================
-- One-time setup for syncing to a REAL iPhone via a free hosted Supabase project.
-- Steps (see SYNC-HANDOFF.md): create a project at supabase.com → open the SQL
-- editor → paste ALL of this → Run. Then copy your Project URL + anon key into
-- Buddy's Mac Settings. Safe to run more than once (create-if-not-exists / drops).
--
-- This is the three migrations (buddy_state + the CAS upgrade + hardening) concatenated, in order.
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

-- Buddy sync — service hardening (pre-requisite for hosting strangers).
--
-- The anon (publishable) key ships inside the app by design, so the server must
-- assume every endpoint is world-callable. This migration adds the four guards
-- that make that safe, without changing the sync contract:
--
--   1. SIZE CAP      — buddy_push rejects blobs over 256 KB (a year of Buddy is a few KB).
--   2. CREATE LIMIT  — new-bucket creation is throttled PER IP (never a global cap:
--                      a public global number is a denial-of-service lever — an
--                      attacker could burn it at 00:01 and lock everyone out).
--   3. DELETE        — buddy_delete(key) lets a user erase their row ("Erase my
--                      cloud data" in Settings). Also the EU right-to-erasure path.
--   4. STATS         — an integers-only `stats` jsonb beside the (soon encrypted)
--                      blob + a `pushes` counter. Metrics are counts, never content;
--                      the server REJECTS non-numeric stats values to enforce it.
--
-- Self-hosters: the tunables live in the CONSTANTS block inside buddy_push.
-- Safe to run more than once (create-if-not-exists / create-or-replace).

-- ---------------------------------------------------------------------------
-- Columns: metrics live beside the blob, never inside it.
alter table public.buddy_state add column if not exists stats  jsonb;
alter table public.buddy_state add column if not exists pushes bigint not null default 0;

-- ---------------------------------------------------------------------------
-- Per-IP bucket-creation log. RLS on, no policies — same posture as buddy_state:
-- direct access denied; only the SECURITY DEFINER functions touch it.
create table if not exists public.buddy_create_log (
  ip text not null,
  hr timestamptz not null,          -- the hour bucket (date_trunc('hour', now()))
  n  int  not null default 0,
  primary key (ip, hr)
);
alter table public.buddy_create_log enable row level security;

-- ---------------------------------------------------------------------------
-- PUSH — same CAS contract, now guarded. Extra optional p_stats keeps old
-- clients calling {p_key,p_blob,p_expected,p_device} working unchanged.
drop function if exists public.buddy_push(text, jsonb, bigint, text);
create or replace function public.buddy_push(
  p_key text, p_blob jsonb, p_expected bigint,
  p_device text default null, p_stats jsonb default null
)
returns table(ok boolean, blob jsonb, version bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  -- CONSTANTS (self-hosters: tune here) ------------------------------------
  c_max_blob_bytes  int := 262144;  -- 256 KB. A year of Buddy state is a few KB.
  c_max_stats_bytes int := 1024;    -- stats is a handful of integers.
  c_creates_per_ip_per_hour int := 20;  -- pairing a device creates ONE bucket.
  ---------------------------------------------------------------------------
  cur_version bigint;
  req_ip text;
  fwd_parts text[];
  ip_inet inet;
  hour_bucket timestamptz := date_trunc('hour', now());
  ip_creates int;
begin
  -- Guard 1: size caps. Distinguishable messages so diagnostics can tell these
  -- from a network failure (never echo blob content back).
  if pg_column_size(p_blob) > c_max_blob_bytes then
    raise exception 'buddy: blob exceeds size limit';
  end if;
  if p_stats is not null and pg_column_size(p_stats) > c_max_stats_bytes then
    raise exception 'buddy: stats exceeds size limit';
  end if;

  -- Guard 4: stats is counts, never content — every value must be a number.
  if p_stats is not null and exists (
    select 1 from jsonb_each(p_stats) where jsonb_typeof(value) <> 'number'
  ) then
    raise exception 'buddy: stats must contain numbers only';
  end if;

  -- Lock the row (if any) so concurrent pushes serialize on the CAS check.
  select bs.version into cur_version from public.buddy_state bs where bs.owner_id = p_key for update;

  if cur_version is null then
    -- No row yet: only a first-writer (expected = 0) may create it.
    if coalesce(p_expected, 0) <> 0 then
      return query select false, null::jsonb, 0::bigint;
      return;
    end if;

    -- Guard 2: per-IP creation throttle. PostgREST exposes the request headers;
    -- when they're absent (psql, tests, supabase db reset) the call is local and
    -- trusted, so the throttle is skipped.
    -- Scan x-forwarded-for RIGHT TO LEFT and take the first PUBLIC address: the
    -- client controls the leftmost elements (a spoofable first element would be
    -- free throttle evasion), while proxies append on the right — but the ingress
    -- may also append its own INTERNAL hop (10.x etc.), so "last element" alone
    -- can be a private address and would silently disable the throttle. Private/
    -- loopback addresses are skipped both as hops (keep scanning left) and as the
    -- final answer (local dev stack + test harnesses are never throttled).
    req_ip := '';
    fwd_parts := string_to_array(coalesce(
      current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',');
    for i in reverse coalesce(array_length(fwd_parts, 1), 0) .. 1 loop
      begin ip_inet := trim(fwd_parts[i])::inet; exception when others then continue; end;
      if ip_inet <<= any (array[
        '10.0.0.0/8','172.16.0.0/12','192.168.0.0/16','127.0.0.0/8','169.254.0.0/16',
        '::1/128','fc00::/7','fe80::/10']::inet[]) then
        continue;   -- internal hop or local caller — keep scanning leftward
      end if;
      req_ip := host(ip_inet);
      exit;
    end loop;
    if req_ip <> '' then
      -- Opportunistic cleanup keeps the log tiny without pg_cron.
      delete from public.buddy_create_log where hr < now() - interval '48 hours';
      insert into public.buddy_create_log(ip, hr, n) values (req_ip, hour_bucket, 1)
        on conflict (ip, hr) do update set n = buddy_create_log.n + 1
        returning n into ip_creates;
      if ip_creates > c_creates_per_ip_per_hour then
        raise exception 'buddy: too many new sync setups from this network — try again later';
      end if;
    end if;

    insert into public.buddy_state(owner_id, blob, device, version, updated_at, stats, pushes)
      values (p_key, p_blob, p_device, 1, now(), p_stats, 1);
    return query select true, p_blob, 1::bigint;
    return;
  end if;

  if p_expected = cur_version then
    update public.buddy_state
      set blob = p_blob, device = p_device, version = cur_version + 1, updated_at = now(),
          stats = coalesce(p_stats, buddy_state.stats), pushes = buddy_state.pushes + 1
      where owner_id = p_key;
    return query select true, p_blob, cur_version + 1;
    return;
  end if;

  -- Version mismatch → someone else wrote. Hand back the current state; client re-merges + retries.
  return query select false,
    (select bs.blob from public.buddy_state bs where bs.owner_id = p_key),
    cur_version;
end $$;

-- ---------------------------------------------------------------------------
-- DELETE — erase the one row for this key. Same capability model as pull/push:
-- you can only delete what you can already read/write (you hold the syncKey).
create or replace function public.buddy_delete(p_key text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare n int;
begin
  delete from public.buddy_state where owner_id = p_key;
  get diagnostics n = row_count;
  return n > 0;
end $$;

-- ---------------------------------------------------------------------------
-- Lock down EXECUTE to the API roles only (RLS still denies direct table access).
revoke all on function public.buddy_push(text, jsonb, bigint, text, jsonb) from public;
revoke all on function public.buddy_delete(text) from public;
grant execute on function public.buddy_push(text, jsonb, bigint, text, jsonb) to anon, authenticated;
grant execute on function public.buddy_delete(text) to anon, authenticated;
