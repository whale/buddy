-- Buddy sync — SERVER WIRE FLOOR (SYNC-COMPAT.md).
--
-- Why this exists: the client-side refuse-to-clobber (dist/index.html syncOnce +
-- makeEncryptedStore, ios SyncEngine) protects any client that CAN read the wire
-- header. It cannot reach a FROZEN pre-header peer — a v0.1.0 phone that writes
-- raw plaintext and can never be changed. That peer clobbered a wire-2 row in the
-- 2026-07-18 incident. The server is the one chokepoint BOTH clients transit, and
-- now that the triage header (b/wire/crypto/minReader) is CLEARTEXT it can read it
-- WITHOUT the E2E key. So the floor lives here: reject any push whose blob is below
-- the configured wire floor.
--
-- ROLLOUT (readers-before-writers): ships DISABLED (floor 0 = no rejection), so it
-- is a no-op until every device runs a wire-2 build. AFTER the Mac + iOS wire-2
-- release has saturated, raise it:  select public.buddy_set_wire_floor(2);
-- Lower it back to 0 to disable. NEVER raise it before saturation or you lock out
-- your own not-yet-updated clients.

-- Single-row config table holding the floor. Default 0 = disabled.
create table if not exists public.buddy_sync_config (
  id         int primary key default 1,
  wire_floor int not null default 0,
  check (id = 1)
);
insert into public.buddy_sync_config (id, wire_floor)
  values (1, 0) on conflict (id) do nothing;

-- Admin helper — set the floor (service role only; not granted to anon/authenticated).
create or replace function public.buddy_set_wire_floor(p_floor int)
returns int
language sql
security definer
set search_path = public
as $$
  update public.buddy_sync_config set wire_floor = greatest(0, p_floor) where id = 1
  returning wire_floor;
$$;
revoke all on function public.buddy_set_wire_floor(int) from public, anon, authenticated;

-- A blob passes the floor iff it is a wire-2+ envelope whose `wire` >= floor.
-- Plaintext / legacy {enc:1} rows have no top-level `b:'buddy'` + numeric `wire`,
-- so they are BELOW any floor >= 1 and get rejected once the floor is raised.
create or replace function public.buddy_blob_wire(p_blob jsonb)
returns int
language sql
immutable
as $$
  select case
    when p_blob ? 'b' and p_blob->>'b' = 'buddy'
         and jsonb_typeof(p_blob->'wire') = 'number'
    then (p_blob->>'wire')::int
    else 0                                   -- plaintext / legacy envelope = wire 0
  end;
$$;

-- PUSH — CAS with the wire floor enforced up front. Otherwise identical to
-- 20260619210000_buddy_cas.sql; keep the two in lockstep. makeFakeCASStore() in
-- dist/index.html mirrors the CAS half (it does not model the floor — the floor is
-- a server-only backstop, exercised by supabase/tests/buddy_wire_floor_test.sql).
create or replace function public.buddy_push(p_key text, p_blob jsonb, p_expected bigint, p_device text default null)
returns table(ok boolean, blob jsonb, version bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  cur_version bigint;
  v_floor     int;
begin
  select wire_floor into v_floor from public.buddy_sync_config where id = 1;

  -- FLOOR: reject sub-floor writes (a frozen pre-header peer). Hand back the current
  -- row unchanged (ok=false) so a compliant client re-merges — and the old client
  -- simply cannot clobber. version -1 signals "rejected by floor" vs a CAS miss.
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

  return query select false,
    (select bs.blob from public.buddy_state bs where bs.owner_id = p_key),
    cur_version;
end $$;

revoke all on function public.buddy_push(text, jsonb, bigint, text) from public;
grant execute on function public.buddy_push(text, jsonb, bigint, text) to anon, authenticated;
