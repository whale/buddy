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
    -- Take the LAST x-forwarded-for element: the client can send its own header
    -- (a spoofable FIRST element would be free throttle evasion); the proxy APPENDS
    -- the real peer address, so only the last element is trustworthy.
    fwd_parts := string_to_array(coalesce(
      current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',');
    req_ip := trim(fwd_parts[coalesce(array_length(fwd_parts, 1), 1)]);
    -- Private/loopback peers are the local dev stack and test harnesses (supabase
    -- start, XCTest, sync:live) — not the public internet. Don't throttle them.
    begin ip_inet := req_ip::inet; exception when others then ip_inet := null; end;
    if ip_inet is not null and ip_inet <<= any (array[
      '10.0.0.0/8','172.16.0.0/12','192.168.0.0/16','127.0.0.0/8','169.254.0.0/16',
      '::1/128','fc00::/7','fe80::/10']::inet[]) then
      req_ip := '';
    end if;
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
