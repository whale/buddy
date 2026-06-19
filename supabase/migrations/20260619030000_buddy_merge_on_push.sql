-- Buddy sync — STEP 4: replace the interim last-write-wins buddy_push with a
-- server-side MERGE-ON-PUSH that mirrors the client merge() (dist/index.html and
-- ios/.../Sync/BuddyMerge.swift). Whole-doc LWW silently drops one device's edits
-- on any two-device day; this server merge converges to the union, losing nothing.
--
-- Design (matches the adversarially-reviewed plan, IOS-COMPANION-PLAN.md):
--   - Push LOCKS the row (SELECT … FOR UPDATE), merges the incoming blob with the
--     stored blob, writes the merged result, and RETURNS it. The caller adopts the
--     merged blob as its new truth (no separate pull needed after a push).
--   - Per-item version `v` (a counter) decides item ties — NOT wall-clock — so clock
--     skew can't let stale data win. updated_at = now() is only the "synced at" label.
--   - erasedAt is a barrier: a snapshot saved before the latest erase-all is voided.
--   - EMPTY-OVER-FULL guard: a push carrying no tasks/history/tombstones/erase can
--     never overwrite a populated row (protects a fresh phone from wiping a full Mac
--     before it has pulled). Such a push is treated as a no-op pull (returns stored).
--   - Lightweight per-key RATE LIMIT: reject pushes faster than one per second.
--
-- TIMESTAMP UNITS: the Mac stores epoch MILLISECONDS, iOS stores epoch SECONDS
-- (Date.timeIntervalSince1970). buddy_norm_ts() normalizes both to seconds by
-- magnitude (>= 1e12 ⇒ milliseconds ⇒ ÷1000) so savedAt / erasedAt / tombstone
-- deletedAt are comparable across devices. (doneAt is only a rare v-tie breaker and
-- is compared as-is — see buddy_pick_item.)

-- ───────────────────────── helpers (pure) ─────────────────────────

-- Normalize an epoch timestamp to SECONDS. Milliseconds (>= 1e12) ⇒ ÷1000.
create or replace function public.buddy_norm_ts(ts numeric)
returns numeric language sql immutable as $$
  select case
           when ts is null then null
           when ts >= 1e12 then ts / 1000.0
           else ts
         end;
$$;

-- The surviving copy of one today-item present on both sides: higher v wins,
-- tie broken by the more-recent doneAt (best-effort; within-device it's exact).
create or replace function public.buddy_pick_item(x jsonb, y jsonb)
returns jsonb language sql immutable as $$
  select case
    when coalesce((y->>'v')::numeric,1) > coalesce((x->>'v')::numeric,1) then y
    when coalesce((x->>'v')::numeric,1) > coalesce((y->>'v')::numeric,1) then x
    when coalesce((y->>'doneAt')::numeric,0) > coalesce((x->>'doneAt')::numeric,0) then y
    else x
  end;
$$;

-- tombstones union: latest deletedAt per id (normalized to seconds).
create or replace function public.buddy_merge_tombstones(a jsonb, b jsonb)
returns jsonb language plpgsql immutable as $$
declare out jsonb := '{}'::jsonb; k text; v numeric;
begin
  a := coalesce(a,'{}'::jsonb); b := coalesce(b,'{}'::jsonb);
  for k, v in select key, public.buddy_norm_ts(value::text::numeric) from jsonb_each(a) loop
    out := jsonb_set(out, array[k], to_jsonb(v));
  end loop;
  for k, v in select key, public.buddy_norm_ts(value::text::numeric) from jsonb_each(b) loop
    out := jsonb_set(out, array[k], to_jsonb(greatest(coalesce((out->>k)::numeric,0), v)));
  end loop;
  return out;
end $$;

-- today.items merge: primary (newer) order kept, higher v per id wins, tombstoned
-- ids dropped, items present on only one side preserved.
create or replace function public.buddy_merge_items(prim jsonb, sec jsonb, tomb jsonb)
returns jsonb language plpgsql immutable as $$
declare
  out jsonb := '[]'::jsonb; seen jsonb := '{}'::jsonb; idx jsonb := '{}'::jsonb;
  it jsonb; oid text; other jsonb;
begin
  prim := coalesce(prim,'[]'::jsonb); sec := coalesce(sec,'[]'::jsonb); tomb := coalesce(tomb,'{}'::jsonb);
  for it in select value from jsonb_array_elements(sec) loop
    idx := jsonb_set(idx, array[it->>'id'], it);
  end loop;
  for it in select value from jsonb_array_elements(prim) loop
    oid := it->>'id';
    seen := jsonb_set(seen, array[oid], 'true'::jsonb);
    if tomb ? oid then continue; end if;
    other := idx->oid;
    if other is not null then out := out || jsonb_build_array(public.buddy_pick_item(it, other));
    else out := out || jsonb_build_array(it); end if;
  end loop;
  for it in select value from jsonb_array_elements(sec) loop
    oid := it->>'id';
    if seen ? oid then continue; end if;
    if tomb ? oid then continue; end if;
    out := out || jsonb_build_array(it);
  end loop;
  return out;
end $$;

-- One history record (same date) from both sides: positional merge, done-wins.
-- (Mirrors the iOS positional merge; Mac history items also carry ids but the OR on
-- `done` is order-stable because per-day archival is deterministic on both apps.)
create or replace function public.buddy_merge_hist_record(x jsonb, y jsonb)
returns jsonb language plpgsql immutable as $$
declare
  xi jsonb := coalesce(x->'items','[]'::jsonb); yi jsonb := coalesce(y->'items','[]'::jsonb);
  n int := greatest(jsonb_array_length(xi), jsonb_array_length(yi));
  items jsonb := '[]'::jsonb; i int; a jsonb; b jsonb; txt text; dn boolean;
begin
  if n > 0 then
    for i in 0..n-1 loop
      a := xi->i; b := yi->i;
      txt := coalesce(a->>'text', b->>'text', '');
      dn  := coalesce((a->>'done')::boolean,false) or coalesce((b->>'done')::boolean,false);
      items := items || jsonb_build_array(jsonb_build_object('text', txt, 'done', dn));
    end loop;
  end if;
  return jsonb_build_object(
    'date', x->>'date',
    'weekday', coalesce(nullif(x->>'weekday',''), y->>'weekday'),
    'items', items);
end $$;

-- history union by date, newest date first.
create or replace function public.buddy_merge_history(a jsonb, b jsonb)
returns jsonb language plpgsql immutable as $$
declare bydate jsonb := '{}'::jsonb; rec jsonb; d text; out jsonb := '[]'::jsonb;
begin
  a := coalesce(a,'[]'::jsonb); b := coalesce(b,'[]'::jsonb);
  for rec in select value from jsonb_array_elements(a || b) loop
    d := rec->>'date';
    if d is null then continue; end if;
    if bydate ? d then bydate := jsonb_set(bydate, array[d], public.buddy_merge_hist_record(bydate->d, rec));
    else bydate := jsonb_set(bydate, array[d], rec); end if;
  end loop;
  for rec in select value from jsonb_each(bydate) order by key desc loop
    out := out || jsonb_build_array(rec);
  end loop;
  return out;
end $$;

-- deferred union by id, tombstoned ids dropped.
create or replace function public.buddy_merge_deferred(a jsonb, b jsonb, tomb jsonb)
returns jsonb language plpgsql immutable as $$
declare byid jsonb := '{}'::jsonb; ord text[] := '{}'; d jsonb; oid text; out jsonb := '[]'::jsonb; k text;
begin
  a := coalesce(a,'[]'::jsonb); b := coalesce(b,'[]'::jsonb); tomb := coalesce(tomb,'{}'::jsonb);
  for d in select value from jsonb_array_elements(a || b) loop
    oid := d->>'id';
    if oid is null or tomb ? oid then continue; end if;
    if not (byid ? oid) then ord := ord || oid; end if;
    byid := jsonb_set(byid, array[oid], d);
  end loop;
  foreach k in array ord loop out := out || jsonb_build_array(byid->k); end loop;
  return out;
end $$;

-- A snapshot saved before the latest erase-all → its items/history/deferred are void.
create or replace function public.buddy_void_preerase(s jsonb)
returns jsonb language sql immutable as $$
  select jsonb_set(jsonb_set(jsonb_set(
           case when s->'today' is null then s
                else jsonb_set(s, '{today,items}', '[]'::jsonb) end,
           '{history}', '[]'::jsonb), '{deferred}', '[]'::jsonb), '{tombstones}', coalesce(s->'tombstones','{}'::jsonb));
$$;

-- ───────────────────────── the merge ─────────────────────────
-- Pure, commutative, idempotent merge of two whole-state blobs. Mirrors the client
-- merge() field-for-field. Either side may be NULL.
create or replace function public.buddy_merge_blobs(a jsonb, b jsonb)
returns jsonb language plpgsql immutable as $$
declare
  erased numeric; sa numeric; sb numeric;
  na jsonb; nb jsonb; newer jsonb; older jsonb; tomb jsonb;
  ta text; tb text; merged_today jsonb; result jsonb;
begin
  if a is null then return b; end if;
  if b is null then return a; end if;

  erased := greatest(coalesce(public.buddy_norm_ts((a->>'erasedAt')::numeric),0),
                     coalesce(public.buddy_norm_ts((b->>'erasedAt')::numeric),0));
  sa := coalesce(public.buddy_norm_ts((a->>'savedAt')::numeric),0);
  sb := coalesce(public.buddy_norm_ts((b->>'savedAt')::numeric),0);

  na := a; nb := b;
  if erased > 0 and sa < erased then na := public.buddy_void_preerase(a); end if;
  if erased > 0 and sb < erased then nb := public.buddy_void_preerase(b); end if;

  if sa >= sb then newer := na; older := nb; else newer := nb; older := na; end if;
  tomb := public.buddy_merge_tombstones(na->'tombstones', nb->'tombstones');

  ta := na->'today'->>'date'; tb := nb->'today'->>'date';
  if na->'today' is not null and nb->'today' is not null and ta is not distinct from tb then
    merged_today := jsonb_build_object(
      'date', newer->'today'->>'date',
      'morningDone', coalesce((na->'today'->>'morningDone')::boolean,false)
                  or coalesce((nb->'today'->>'morningDone')::boolean,false),
      'items', public.buddy_merge_items(newer->'today'->'items', older->'today'->'items', tomb));
  else
    merged_today := coalesce(newer->'today', older->'today');
  end if;

  result := newer;  -- scalars (settings, pinned, version) come from the newer save
  result := jsonb_set(result, '{today}', coalesce(merged_today, 'null'::jsonb));
  result := jsonb_set(result, '{history}', public.buddy_merge_history(na->'history', nb->'history'));
  result := jsonb_set(result, '{deferred}', public.buddy_merge_deferred(na->'deferred', nb->'deferred', tomb));
  result := jsonb_set(result, '{tombstones}', tomb);
  result := jsonb_set(result, '{savedAt}', to_jsonb(greatest(sa, sb)));
  if erased > 0 then result := jsonb_set(result, '{erasedAt}', to_jsonb(erased));
  else result := result - 'erasedAt'; end if;
  return result;
end $$;

-- True when a blob carries no meaningful state (no tasks, history, deferred,
-- tombstones, or erase). Used by the empty-over-full guard.
create or replace function public.buddy_blob_is_empty(s jsonb)
returns boolean language sql immutable as $$
  select s is null
      or ( coalesce(jsonb_array_length(s->'today'->'items'),0) = 0
       and coalesce(jsonb_array_length(s->'history'),0) = 0
       and coalesce(jsonb_array_length(s->'deferred'),0) = 0
       and coalesce((select count(*) from jsonb_object_keys(coalesce(s->'tombstones','{}'::jsonb))),0) = 0
       and (s->>'erasedAt') is null );
$$;

-- ───────────────────────── push (merge-on-push) ─────────────────────────
-- Add a per-key throttle column for the lightweight rate limit.
alter table public.buddy_state add column if not exists last_push_at timestamptz;

drop function if exists public.buddy_push(text, jsonb, text, timestamptz);

-- Returns the authoritative MERGED blob + its synced-at stamp. The caller replaces
-- its local state with `blob`. p_updated_at is accepted for API compatibility but
-- ignored for conflict resolution (the merge + per-item v are authoritative).
create or replace function public.buddy_push(p_key text, p_blob jsonb, p_device text, p_updated_at timestamptz default null)
returns table(blob jsonb, updated_at timestamptz) language plpgsql security definer set search_path = public as $$
declare existing jsonb; existing_pushed timestamptz; merged jsonb;
begin
  -- Lock this key's row (if any) so concurrent pushes serialize.
  select bs.blob, bs.last_push_at into existing, existing_pushed
    from public.buddy_state bs where bs.owner_id = p_key for update;

  -- Rate limit: at most one push/second per key.
  if existing_pushed is not null and now() - existing_pushed < interval '1 second' then
    raise exception 'rate_limited' using errcode = '54000';
  end if;

  -- Empty-over-full guard: a contentless push never clobbers a populated row.
  -- Treat it as a pull — return what's stored, unchanged.
  if existing is not null and public.buddy_blob_is_empty(p_blob) and not public.buddy_blob_is_empty(existing) then
    return query select existing, (select bs.updated_at from public.buddy_state bs where bs.owner_id = p_key);
    return;
  end if;

  merged := public.buddy_merge_blobs(existing, p_blob);

  insert into public.buddy_state(owner_id, blob, device, updated_at, last_push_at)
    values (p_key, merged, p_device, now(), now())
  on conflict (owner_id) do update
    set blob = excluded.blob, device = excluded.device,
        updated_at = excluded.updated_at, last_push_at = excluded.last_push_at;

  return query select merged, now();
end $$;

revoke all on function public.buddy_push(text, jsonb, text, timestamptz) from public;
grant execute on function public.buddy_push(text, jsonb, text, timestamptz) to anon, authenticated;
-- Internal merge helpers are not granted to API roles (callable only inside buddy_push).
revoke all on function public.buddy_merge_blobs(jsonb, jsonb) from public;
