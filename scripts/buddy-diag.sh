#!/bin/bash
# Buddy diagnostics reader — pretty-print the privacy-safe event log.
# Usage: scripts/buddy-diag.sh [N]        (last N events, default 40)
#        scripts/buddy-diag.sh errors     (only errors/conflicts/watchdog/heals)
# The log: structured JSONL, NO task text ever — event names, counts, versions,
# timings. Written by the Mac app (dist diag()) to the app-data dir; the iOS app
# writes the same schema on-device (surface via a future Settings export).
# Reads the ROTATED file too: append_event rotates to .jsonl.1 and drops the older
# one, so reading only the live file silently throws away half the retained window.
set -uo pipefail
DIR="$HOME/Library/Application Support/fyi.whale.buddy"
LOG="$DIR/buddy-events.jsonl"
OLD="$DIR/buddy-events.jsonl.1"
[ -f "$LOG" ] || [ -f "$OLD" ] || { echo "no event log yet at: $LOG"; exit 0; }

FMT='import sys,json
n=0
for l in sys.stdin:
    l=l.strip()
    if not l: continue
    try: r=json.loads(l)
    except ValueError: continue
    n+=1
    t=r.pop("t",""); e=r.pop("evt","")
    print(f"{t}  {e:26s} {json.dumps(r) if r else chr(34)+chr(34)}")
if n==0: print("(nothing matched — no such events in the retained window)")'

cat_all(){ [ -f "$OLD" ] && cat "$OLD"; [ -f "$LOG" ] && cat "$LOG"; return 0; }

if [ "${1:-}" = "errors" ]; then
  # grep exits 1 when there are simply NO errors — a good outcome, not a failure.
  cat_all | grep -E '"evt":"(sync-error|sync-conflict|sync-degraded|sync-watchdog-reset|edit-guard-healed|adopt-deferred-editing)"' \
    | tail -60 | python3 -c "$FMT"
else
  cat_all | tail -"${1:-40}" | python3 -c "$FMT"
fi
