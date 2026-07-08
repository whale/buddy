#!/bin/bash
# Buddy diagnostics reader — pretty-print the privacy-safe event log.
# Usage: scripts/buddy-diag.sh [N]        (last N events, default 40)
#        scripts/buddy-diag.sh errors     (only errors/conflicts/watchdog/heals)
# The log: structured JSONL, NO task text ever — event names, counts, versions,
# timings. Written by the Mac app (dist diag()) to the app-data dir; the iOS app
# writes the same schema on-device (surface via a future Settings export).
set -euo pipefail
LOG="$HOME/Library/Application Support/fyi.whale.buddy/buddy-events.jsonl"
[ -f "$LOG" ] || { echo "no event log yet at: $LOG"; exit 0; }

if [ "${1:-}" = "errors" ]; then
  grep -E '"evt":"(sync-error|sync-conflict|sync-watchdog-reset|edit-guard-healed|adopt-deferred-editing)"' "$LOG" \
    | tail -60 | python3 -c 'import sys,json
for l in sys.stdin:
    r=json.loads(l); t=r.pop("t",""); e=r.pop("evt","")
    print(f"{t}  {e:26s} {json.dumps(r) if r else chr(34)+chr(34)}")'
else
  tail -"${1:-40}" "$LOG" | python3 -c 'import sys,json
for l in sys.stdin:
    r=json.loads(l); t=r.pop("t",""); e=r.pop("evt","")
    print(f"{t}  {e:26s} {json.dumps(r) if r else chr(34)+chr(34)}")'
fi
