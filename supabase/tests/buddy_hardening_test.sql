-- Live verification of the hardening guards (size cap, per-IP create throttle,
-- buddy_delete, integers-only stats). Run against the local stack:
--   supabase start && supabase db reset
--   psql "$(supabase status -o env | sed -n 's/^DB_URL="\(.*\)"$/\1/p')" -f supabase/tests/buddy_hardening_test.sql
--
-- Aborts on the first failed ASSERT; prints PASS at the end.

\set ON_ERROR_STOP on

do $$
declare
  r record;
  b jsonb := '{"v":1,"note":"ok"}';
  big jsonb;
  failed boolean;
begin
  delete from public.buddy_state where owner_id like 'hard-test%';

  -- 1. Oversized blob is rejected with the distinguishable message.
  big := jsonb_build_object('pad', repeat('x', 300000));
  failed := false;
  begin
    perform * from public.buddy_push('hard-test', big, 0, 'mac');
  exception when others then
    failed := sqlerrm like 'buddy: blob exceeds%';
  end;
  assert failed, 'oversized blob must be rejected';

  -- 2. Stats with a string value is rejected (counts, never content).
  failed := false;
  begin
    perform * from public.buddy_push('hard-test', b, 0, 'mac', '{"active":2,"leak":"secret task"}');
  exception when others then
    failed := sqlerrm like 'buddy: stats must contain numbers only';
  end;
  assert failed, 'non-numeric stats must be rejected';

  -- 3. Numeric stats are stored beside the blob; pushes counts up.
  select * into r from public.buddy_push('hard-test', b, 0, 'mac', '{"active":3,"done":7}');
  assert r.ok and r.version = 1, 'first push with stats should succeed';
  select * into r from public.buddy_push('hard-test', b, 1, 'phone', '{"active":2,"done":8}');
  assert r.ok and r.version = 2, 'second push should succeed';
  perform 1 from public.buddy_state
    where owner_id = 'hard-test' and stats = '{"active":2,"done":8}'::jsonb and pushes = 2;
  assert found, 'stats + pushes must be stored on the row';

  -- 4. Omitting stats keeps the previous stats (old clients keep working).
  select * into r from public.buddy_push('hard-test', b, 2, 'mac');
  assert r.ok and r.version = 3, 'push without stats should succeed';
  perform 1 from public.buddy_state
    where owner_id = 'hard-test' and stats = '{"active":2,"done":8}'::jsonb;
  assert found, 'stats must survive a push that omits them';

  -- 5. Per-IP creation throttle: simulate PostgREST headers with set_config.
  -- Right-to-left scan for the first PUBLIC address: spoofed client-sent elements
  -- (left) are ignored, and an ingress-appended INTERNAL hop (right) is skipped —
  -- so all of these count against 203.0.113.9 regardless of header shape.
  delete from public.buddy_create_log where ip = '203.0.113.9';
  for i in 1..20 loop
    if i % 2 = 0 then
      -- spoofed first element + real IP last
      perform set_config('request.headers',
        '{"x-forwarded-for":"10.9.9.' || i || ', 203.0.113.9"}', true);
    else
      -- real IP followed by an internal ingress hop (Kond/LB appends its own)
      perform set_config('request.headers',
        '{"x-forwarded-for":"203.0.113.9, 10.0.0.5"}', true);
    end if;
    perform * from public.buddy_push('hard-test-ip-' || i, b, 0, 'mac');
  end loop;
  failed := false;
  begin
    perform * from public.buddy_push('hard-test-ip-21', b, 0, 'mac');
  exception when others then
    failed := sqlerrm like 'buddy: too many new sync setups%';
  end;
  assert failed, '21st creation from one real IP must be rejected (spoofed first element ignored)';

  -- 5b. REJECTED attempts must not increment the counter — a retrying client
  -- (Buddy polls every 1.5s) must not lock itself out of the NEXT window.
  for i in 1..30 loop
    begin
      perform * from public.buddy_push('hard-test-ip-rej-' || i, b, 0, 'mac');
    exception when others then null;   -- rejected, repeatedly
    end;
  end loop;
  perform 1 from public.buddy_create_log where ip = '203.0.113.9' and n = 20;
  assert found, 'counter must stay AT the cap after rejected attempts (found n<>20)';

  -- 6. The throttle only guards CREATION — updates from the same IP still work.
  select * into r from public.buddy_push('hard-test-ip-1', b, 1, 'mac');
  assert r.ok, 'updates must not be throttled';

  -- 7. Private/loopback peers (local dev stack, test harnesses) are never throttled.
  perform set_config('request.headers', '{"x-forwarded-for":"192.168.65.1"}', true);
  for i in 1..25 loop
    perform * from public.buddy_push('hard-test-priv-' || i, b, 0, 'mac');
  end loop;
  select * into r from public.buddy_push('hard-test-priv-26', b, 0, 'mac');
  assert r.ok, 'private-range IPs must not be throttled (local dev/tests)';
  perform set_config('request.headers', '', true);

  -- 8. buddy_delete removes the row; deleting again reports false.
  assert public.buddy_delete('hard-test'), 'delete should report the row was removed';
  perform * from public.buddy_pull('hard-test');
  assert not found, 'row must be gone after delete';
  assert not public.buddy_delete('hard-test'), 'second delete should report nothing to remove';

  delete from public.buddy_state where owner_id like 'hard-test%';
  delete from public.buddy_create_log where ip = '203.0.113.9';
  delete from public.buddy_state where owner_id like 'hard-test%';
  raise notice 'hardening: all 8 checks passed';
end $$;

\echo 'ALL HARDENING TESTS PASSED'
