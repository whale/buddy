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
