-- Step 4 verification — run against a live local DB once it's up:
--   1. Start OrbStack (the Docker app)
--   2. cd supabase && supabase start
--   3. supabase db reset            # applies all migrations
--   4. psql "$(supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '\"')" -f tests/buddy_merge_on_push_test.sql
--
-- Every check is an ASSERT — the script raises and aborts on the first failure,
-- and prints "ALL MERGE-ON-PUSH TESTS PASSED" at the end on success.
-- Mirrors the client mergeTest()/BuddyMergeTests scenarios + the server guards.

\set ON_ERROR_STOP on

do $$
declare
  m jsonb; r record;
  A jsonb; B jsonb;
begin
  -- 1. Different-task edits on two devices BOTH survive.
  A := jsonb_build_object('savedAt', 2000, 'today', jsonb_build_object('date','2026-06-19','items',
        jsonb_build_array(jsonb_build_object('id','t1','text','A-edit','state','neutral','v',2),
                          jsonb_build_object('id','t2','text','keep','state','neutral','v',1))));
  B := jsonb_build_object('savedAt', 1900, 'today', jsonb_build_object('date','2026-06-19','items',
        jsonb_build_array(jsonb_build_object('id','t1','text','old','state','neutral','v',1),
                          jsonb_build_object('id','t2','text','B-edit','state','neutral','v',2))));
  m := public.buddy_merge_blobs(A, B);
  assert (select jsonb_path_query_first(m, '$.today.items[*] ? (@.id == "t1").text')) = '"A-edit"', 'different-task edits: t1';
  assert (select jsonb_path_query_first(m, '$.today.items[*] ? (@.id == "t2").text')) = '"B-edit"', 'different-task edits: t2';

  -- 2. Higher per-item v wins regardless of savedAt.
  m := public.buddy_merge_blobs(
        jsonb_build_object('savedAt',1000,'today',jsonb_build_object('date','d','items',
          jsonb_build_array(jsonb_build_object('id','x','text','new','v',3)))),
        jsonb_build_object('savedAt',5000,'today',jsonb_build_object('date','d','items',
          jsonb_build_array(jsonb_build_object('id','x','text','stale','v',2)))));
  assert (select jsonb_path_query_first(m, '$.today.items[*] ? (@.id == "x").text')) = '"new"', 'higher v wins';

  -- 3. Tombstone wins — deleted id not resurrected.
  m := public.buddy_merge_blobs(
        jsonb_build_object('savedAt',2000,'tombstones',jsonb_build_object('g',1500),'today',jsonb_build_object('date','d','items','[]'::jsonb)),
        jsonb_build_object('savedAt',1000,'today',jsonb_build_object('date','d','items',
          jsonb_build_array(jsonb_build_object('id','g','text','ghost','v',1)))));
  assert jsonb_array_length(m->'today'->'items') = 0, 'tombstone wins: g dropped';
  assert (m->'tombstones'->>'g') = '1500', 'tombstone wins: kept';

  -- 4. erasedAt barrier voids pre-erase items + history.
  m := public.buddy_merge_blobs(
        jsonb_build_object('savedAt',9000,'erasedAt',8000,'today',jsonb_build_object('date','d','items','[]'::jsonb),'history','[]'::jsonb),
        jsonb_build_object('savedAt',5000,'today',jsonb_build_object('date','d','items',
          jsonb_build_array(jsonb_build_object('id','z','text','pre-erase','v',9))),
          'history', jsonb_build_array(jsonb_build_object('date','2026-06-01','weekday','Mon','items',
            jsonb_build_array(jsonb_build_object('text','old','done',true))))));
  assert jsonb_array_length(m->'today'->'items') = 0, 'erasedAt voids items';
  assert jsonb_array_length(m->'history') = 0, 'erasedAt voids history';
  assert (m->>'erasedAt')::numeric = 8000, 'erasedAt kept';

  -- 5. History union by date + done-wins.
  m := public.buddy_merge_blobs(
        jsonb_build_object('savedAt',2000,'history',jsonb_build_array(
          jsonb_build_object('date','2026-06-18','weekday','Thu','items',jsonb_build_array(jsonb_build_object('text','task','done',true))))),
        jsonb_build_object('savedAt',1000,'history',jsonb_build_array(
          jsonb_build_object('date','2026-06-18','weekday','Thu','items',jsonb_build_array(jsonb_build_object('text','task','done',false))),
          jsonb_build_object('date','2026-06-17','weekday','Wed','items',jsonb_build_array(jsonb_build_object('text','other','done',true))))));
  assert jsonb_array_length(m->'history') = 2, 'history union: 2 days';
  assert (select jsonb_path_query_first(m, '$.history[*] ? (@.date == "2026-06-18").items[0].done')) = 'true', 'history done-wins';

  -- 6. One-sided items kept.
  m := public.buddy_merge_blobs(
        jsonb_build_object('savedAt',2000,'today',jsonb_build_object('date','d','items',jsonb_build_array(jsonb_build_object('id','a','text','aa','v',1)))),
        jsonb_build_object('savedAt',1000,'today',jsonb_build_object('date','d','items',jsonb_build_array(jsonb_build_object('id','b','text','bb','v',1)))));
  assert jsonb_array_length(m->'today'->'items') = 2, 'one-sided items kept';

  -- 7. Commutative on the id set.
  assert (select array_agg(x order by x) from jsonb_array_elements_text(
            (select jsonb_agg(e->>'id') from jsonb_array_elements(public.buddy_merge_blobs(A,B)->'today'->'items') e)) x)
       = (select array_agg(x order by x) from jsonb_array_elements_text(
            (select jsonb_agg(e->>'id') from jsonb_array_elements(public.buddy_merge_blobs(B,A)->'today'->'items') e)) x),
       'commutative on id set';

  -- 8. Idempotent — merge(a,a) preserves items + versions.
  m := public.buddy_merge_blobs(A, A);
  assert (select jsonb_path_query_first(m, '$.today.items[*] ? (@.id == "t1").v')) = '2', 'idempotent: v preserved';
  assert jsonb_array_length(m->'today'->'items') = 2, 'idempotent: item count';

  -- 9. NULL inputs tolerated.
  assert public.buddy_merge_blobs(null, A) = A, 'null left → right';
  assert public.buddy_merge_blobs(A, null) = A, 'null right → left';
  assert public.buddy_merge_blobs(null, null) is null, 'both null → null';

  -- 10. Timestamp normalization: Mac ms (8000000) and iOS s (7000) compare correctly.
  --     The ms erase (=8000s normalized) is later than the s save (5000s) → voids it.
  m := public.buddy_merge_blobs(
        jsonb_build_object('savedAt',9000000,'erasedAt',8000000,'today',jsonb_build_object('date','d','items','[]'::jsonb)),
        jsonb_build_object('savedAt',5000,'today',jsonb_build_object('date','d','items',
          jsonb_build_array(jsonb_build_object('id','z','text','pre-erase','v',1)))));
  assert jsonb_array_length(m->'today'->'items') = 0, 'ts-normalize: ms erase voids seconds save';

  raise notice 'pure merge: 10 scenarios passed';
end $$;

-- Integration: buddy_push end-to-end (merge-on-push, empty-over-full, return shape).
do $$
declare r record; full_blob jsonb; empty_blob jsonb;
begin
  delete from public.buddy_state where owner_id = 'test-key';

  full_blob  := jsonb_build_object('savedAt',1000,'today',jsonb_build_object('date','d','items',
                  jsonb_build_array(jsonb_build_object('id','a','text','first','state','neutral','v',1))));
  empty_blob := jsonb_build_object('savedAt',2000,'today',jsonb_build_object('date','d','items','[]'::jsonb),'history','[]'::jsonb);

  -- First push seeds the row.
  select * into r from public.buddy_push('test-key', full_blob, 'mac');
  assert jsonb_array_length(r.blob->'today'->'items') = 1, 'push: row seeded';

  -- Empty-over-full guard: an empty push returns the stored full blob, doesn't wipe it.
  -- (sleep past the 1s rate limit first)
  perform pg_sleep(1.1);
  select * into r from public.buddy_push('test-key', empty_blob, 'fresh-phone');
  assert jsonb_array_length(r.blob->'today'->'items') = 1, 'empty-over-full: stored kept';

  -- A real second-device push merges (adds a new task).
  perform pg_sleep(1.1);
  select * into r from public.buddy_push('test-key',
    jsonb_build_object('savedAt',3000,'today',jsonb_build_object('date','d','items',
      jsonb_build_array(jsonb_build_object('id','b','text','second','state','neutral','v',1)))), 'phone');
  assert jsonb_array_length(r.blob->'today'->'items') = 2, 'merge-on-push: both tasks present';

  -- Rate limit: an immediate second push is rejected.
  begin
    select * into r from public.buddy_push('test-key', full_blob, 'mac');
    raise exception 'rate limit did NOT fire';
  exception when sqlstate '54000' then
    null;  -- expected
  end;

  delete from public.buddy_state where owner_id = 'test-key';
  raise notice 'buddy_push integration: merge-on-push + empty-over-full + rate-limit passed';
end $$;

\echo 'ALL MERGE-ON-PUSH TESTS PASSED'
