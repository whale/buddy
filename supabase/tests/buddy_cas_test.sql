-- Live verification of the dumb CAS server (buddy_pull / buddy_push).
-- Run against the local stack once it's up:
--   supabase start && supabase db reset
--   psql "$(supabase status -o env | sed -n 's/^DB_URL="\(.*\)"$/\1/p')" -f supabase/tests/buddy_cas_test.sql
--
-- Asserts the exact contract the client fake stores mirror (makeFakeCASStore /
-- InMemoryCASStore). Aborts on the first failed ASSERT; prints PASS at the end.

\set ON_ERROR_STOP on

do $$
declare r record; b1 jsonb := '{"v":1,"note":"first"}'; b2 jsonb := '{"v":2,"note":"second"}';
begin
  delete from public.buddy_state where owner_id = 'cas-test';

  -- 1. Pull on an absent key returns 0 rows.
  perform * from public.buddy_pull('cas-test');
  assert not found, 'absent key should return no row';

  -- 2. First push must use expected_version 0 → inserts at version 1.
  select * into r from public.buddy_push('cas-test', b1, 0, 'mac');
  assert r.ok and r.version = 1, format('first push: ok=%s version=%s', r.ok, r.version);

  -- 3. First push with a non-zero expected on an absent row is rejected.
  delete from public.buddy_state where owner_id = 'cas-test2';
  select * into r from public.buddy_push('cas-test2', b1, 5, 'mac');
  assert (not r.ok) and r.version = 0, 'non-zero expected on absent row must fail';

  -- 4. Pull returns the stored blob + version.
  select * into r from public.buddy_pull('cas-test');
  assert r.version = 1 and r.blob = b1, format('pull after first push: version=%s', r.version);

  -- 5. Stale push (expected 0 when stored is 1) is rejected, returns CURRENT state.
  select * into r from public.buddy_push('cas-test', b2, 0, 'phone');
  assert (not r.ok) and r.version = 1 and r.blob = b1, 'stale push must be rejected with current state';

  -- 6. Matching push (expected 1) succeeds, server increments to 2.
  select * into r from public.buddy_push('cas-test', b2, 1, 'phone');
  assert r.ok and r.version = 2 and r.blob = b2, format('matching push: ok=%s version=%s', r.ok, r.version);

  -- 7. Re-using the now-stale expected (1) is rejected, returns version 2 + b2.
  select * into r from public.buddy_push('cas-test', b1, 1, 'mac');
  assert (not r.ok) and r.version = 2 and r.blob = b2, 'reused stale expected must be rejected';

  delete from public.buddy_state where owner_id = 'cas-test';
  delete from public.buddy_state where owner_id = 'cas-test2';
  raise notice 'CAS contract: all 7 checks passed';
end $$;

\echo 'ALL CAS TESTS PASSED'
