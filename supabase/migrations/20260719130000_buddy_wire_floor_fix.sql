-- Buddy sync — WIRE FLOOR, corrected (supersedes 20260719120000_buddy_wire_floor.sql).
--
-- BUG being fixed (review 2026-07-19): the first floor migration put the floor check on
-- a 4-arg buddy_push(text,jsonb,bigint,text). But the LIVE function is the 5-arg
-- buddy_push(text,jsonb,bigint,text,jsonb) (p_stats), created by _buddy_hardening +
-- _buddy_throttle_no_reject_count. Every real Mac/iOS client sends p_stats, so PostgREST
-- routed them to the UNFLOORED 5-arg function — the floor did nothing, and the two
-- overloads risked a PGRST203 "ambiguous function" error for no-stats callers.
--
-- This migration: (1) drops the stray 4-arg overload, (2) re-ensures the floor config +
-- helpers, (3) redefines the REAL 5-arg buddy_push = the throttle version verbatim WITH
-- the floor check inserted. Verified by supabase/tests/buddy_wire_floor_test.sql (which
-- now calls buddy_push WITH p_stats, i.e. the real path).

-- (1) Remove the dead overload so only the 5-arg function exists (no ambiguity).
drop function if exists public.buddy_push(text, jsonb, bigint, text);

-- (2) Floor config + helpers (idempotent — the first migration may or may not have run).
create table if not exists public.buddy_sync_config (
  id int primary key default 1,
  wire_floor int not null default 0,
  check (id = 1)
);
insert into public.buddy_sync_config (id, wire_floor) values (1, 0) on conflict (id) do nothing;

create or replace function public.buddy_set_wire_floor(p_floor int)
returns int language sql security definer set search_path = public as $$
  update public.buddy_sync_config set wire_floor = greatest(0, p_floor) where id = 1
  returning wire_floor;
$$;
revoke all on function public.buddy_set_wire_floor(int) from public, anon, authenticated;

-- Cleartext wire of a blob: a wire-2+ envelope reports its `wire`; plaintext / legacy
-- {enc:1} have no top-level b='buddy'+numeric wire, so they read as 0 (below any floor).
create or replace function public.buddy_blob_wire(p_blob jsonb)
returns int language sql immutable set search_path = public as $$
  select case
    when p_blob ? 'b' and p_blob->>'b' = 'buddy' and jsonb_typeof(p_blob->'wire') = 'number'
    then (p_blob->>'wire')::int else 0 end;
$$;

-- (3) The REAL 5-arg buddy_push — _buddy_throttle_no_reject_count verbatim, plus the
-- floor check. Keep the two in lockstep; the ONLY addition is the v_floor block.
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
  c_max_blob_bytes  int := 262144;  -- 256 KB
  c_max_stats_bytes int := 1024;
  c_creates_per_ip_per_hour int := 20;
  cur_version bigint;
  req_ip text;
  fwd_parts text[];
  ip_inet inet;
  hour_bucket timestamptz := date_trunc('hour', now());
  ip_creates int;
  v_floor int;
begin
  if pg_column_size(p_blob) > c_max_blob_bytes then
    raise exception 'buddy: blob exceeds size limit';
  end if;
  if p_stats is not null and pg_column_size(p_stats) > c_max_stats_bytes then
    raise exception 'buddy: stats exceeds size limit';
  end if;
  if p_stats is not null and exists (
    select 1 from jsonb_each(p_stats) where jsonb_typeof(value) <> 'number'
  ) then
    raise exception 'buddy: stats must contain numbers only';
  end if;

  -- WIRE FLOOR (SYNC-COMPAT.md): reject a write whose cleartext wire header is below the
  -- configured floor — the only lever that stops a FROZEN pre-header client (v0.1.0) from
  -- clobbering a wire-2 row. Ships at 0 (no-op); raise via buddy_set_wire_floor(2) only
  -- AFTER the wire-2 build saturates. Rejected → ok=false, version -1 (distinct from a CAS
  -- miss's real version), current row handed back UNCHANGED so nothing is lost.
  select wire_floor into v_floor from public.buddy_sync_config where id = 1;
  if coalesce(v_floor, 0) > 0 and public.buddy_blob_wire(p_blob) < v_floor then
    return query select false,
      (select bs.blob from public.buddy_state bs where bs.owner_id = p_key),
      -1::bigint;
    return;
  end if;

  select bs.version into cur_version from public.buddy_state bs where bs.owner_id = p_key for update;

  if cur_version is null then
    if coalesce(p_expected, 0) <> 0 then
      return query select false, null::jsonb, 0::bigint;
      return;
    end if;

    req_ip := '';
    fwd_parts := string_to_array(coalesce(
      current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',');
    for i in reverse coalesce(array_length(fwd_parts, 1), 0) .. 1 loop
      begin ip_inet := trim(fwd_parts[i])::inet; exception when others then continue; end;
      if ip_inet <<= any (array[
        '10.0.0.0/8','172.16.0.0/12','192.168.0.0/16','127.0.0.0/8','169.254.0.0/16',
        '::1/128','fc00::/7','fe80::/10']::inet[]) then
        continue;
      end if;
      req_ip := host(ip_inet);
      exit;
    end loop;
    if req_ip <> '' then
      delete from public.buddy_create_log where hr < now() - interval '48 hours';
      select n into ip_creates from public.buddy_create_log where ip = req_ip and hr = hour_bucket;
      if coalesce(ip_creates, 0) >= c_creates_per_ip_per_hour then
        raise exception 'buddy: too many new sync setups from this network — try again later';
      end if;
      insert into public.buddy_create_log(ip, hr, n) values (req_ip, hour_bucket, 1)
        on conflict (ip, hr) do update set n = buddy_create_log.n + 1;
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

  return query select false,
    (select bs.blob from public.buddy_state bs where bs.owner_id = p_key),
    cur_version;
end $$;

revoke all on function public.buddy_push(text, jsonb, bigint, text, jsonb) from public;
grant execute on function public.buddy_push(text, jsonb, bigint, text, jsonb) to anon, authenticated;
