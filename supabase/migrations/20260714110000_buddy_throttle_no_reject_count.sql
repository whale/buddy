-- Throttle fix: REJECTED creation attempts must not increment the per-IP counter.
--
-- Found by the two-device live gate: Buddy's sync loop retries every ~1.5s by
-- design, so a client that hits the creation cap once keeps incrementing its own
-- counter while being rejected — locking itself (and its whole NAT) out into the
-- NEXT hourly window too, indefinitely while the app is open. The counter now
-- counts only ALLOWED creations: check first, increment after. (A concurrent
-- burst can overshoot the cap by a few — it's an abuse ceiling, not an exact
-- quota.) Existing counters are cleared because their values mix allowed and
-- rejected attempts under the old semantics.

delete from public.buddy_create_log;

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
      -- CHECK FIRST, increment only when allowed: a rejected attempt must not
      -- count, or a retrying client (Buddy polls every 1.5s) locks itself out
      -- of every subsequent window while the app is open.
      select n into ip_creates from public.buddy_create_log
        where ip = req_ip and hr = hour_bucket;
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

  -- Version mismatch → someone else wrote. Hand back the current state; client re-merges + retries.
  return query select false,
    (select bs.blob from public.buddy_state bs where bs.owner_id = p_key),
    cur_version;
end $$;

revoke all on function public.buddy_push(text, jsonb, bigint, text, jsonb) from public;
grant execute on function public.buddy_push(text, jsonb, bigint, text, jsonb) to anon, authenticated;
