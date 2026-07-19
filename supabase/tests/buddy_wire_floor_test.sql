-- Live verification of the SERVER WIRE FLOOR (20260719120000_buddy_wire_floor.sql).
-- Run against the local stack once it's up:
--   supabase start && supabase db reset
--   psql "$(supabase status -o env | sed -n 's/^DB_URL="\(.*\)"$/\1/p')" -f supabase/tests/buddy_wire_floor_test.sql
--
-- Asserts: floor 0 is a no-op (backward compatible); floor 2 rejects plaintext /
-- legacy / sub-floor writes but ACCEPTS wire-2 envelopes; the stored row is never
-- clobbered by a rejected write. Aborts on the first failed ASSERT; prints PASS.

\set ON_ERROR_STOP on

do $$
declare
  r          record;
  plaintext  jsonb := '{"today":{"date":"2026-07-19","items":[]},"savedAt":1}';
  legacy_env jsonb := '{"enc":1,"iv":"x","ct":"y"}';
  wire2_env  jsonb := '{"b":"buddy","wire":2,"crypto":"aes256gcm.hkdf.v1","minReader":2,"iv":"x","ct":"y"}';
begin
  delete from public.buddy_state where owner_id = 'floor-test';
  perform public.buddy_set_wire_floor(0);

  -- 0. buddy_blob_wire reads the cleartext header (0 for non-envelopes).
  assert public.buddy_blob_wire(wire2_env) = 2, 'wire-2 envelope reports wire 2';
  assert public.buddy_blob_wire(plaintext) = 0, 'plaintext reports wire 0';
  assert public.buddy_blob_wire(legacy_env) = 0, 'legacy {enc:1} reports wire 0';

  -- 1. FLOOR 0 (default) = no-op: a plaintext write is accepted (backward compatible).
  select * into r from public.buddy_push('floor-test', plaintext, 0, 'old');
  assert r.ok and r.version = 1, format('floor 0 accepts plaintext: ok=%s v=%s', r.ok, r.version);

  -- 2. Raise the floor to 2.
  assert public.buddy_set_wire_floor(2) = 2, 'floor set to 2';

  -- 3. A wire-2 envelope PASSES the floor (CAS still applies: expected = current version 1).
  select * into r from public.buddy_push('floor-test', wire2_env, 1, 'mac');
  assert r.ok and r.version = 2, format('floor 2 accepts wire-2: ok=%s v=%s', r.ok, r.version);

  -- 4. A frozen old client's PLAINTEXT write is REJECTED (version -1), row unchanged.
  select * into r from public.buddy_push('floor-test', plaintext, 2, 'old');
  assert (not r.ok) and r.version = -1, format('floor 2 rejects plaintext: ok=%s v=%s', r.ok, r.version);
  select * into r from public.buddy_pull('floor-test');
  assert r.version = 2 and (r.blob ? 'b'), 'rejected write did NOT clobber the wire-2 row';

  -- 5. A legacy {enc:1} write is ALSO rejected once the floor is up.
  select * into r from public.buddy_push('floor-test', legacy_env, 2, 'old');
  assert (not r.ok) and r.version = -1, 'floor 2 rejects legacy {enc:1}';

  -- 6. Lower the floor back to 0 → plaintext accepted again (reversible).
  perform public.buddy_set_wire_floor(0);
  select * into r from public.buddy_push('floor-test', plaintext, 2, 'old');
  assert r.ok, 'floor 0 accepts plaintext again';

  delete from public.buddy_state where owner_id = 'floor-test';
  perform public.buddy_set_wire_floor(0);
  raise notice 'PASS — buddy_wire_floor';
end $$;
