#!/usr/bin/env bash
# Cut an iOS TestFlight build AND CONFIRM it landed at the source of truth.
#
# Why this exists (2026-07-19): fastlane's success was reported when it hadn't
# succeeded — twice — because the command was piped (`| tail`) or had a trailing
# `; echo`, so the exit code read belonged to the wrong command. And "fastlane
# uploaded" ≠ "visible on TestFlight" (Apple processes for a few minutes). This
# wrapper removes both traps: it runs fastlane un-piped (real exit code), then
# POLLS App Store Connect until a genuinely NEW build appears — or fails loudly.
#
# Usage:  pnpm ios:beta
set -euo pipefail
cd "$(dirname "$0")/.."
ASC="node scripts/buddy-asc-builds.mjs"

echo "▸ baseline — Apple's current latest build:"
BEFORE="$($ASC | head -1 || true)"
echo "    ${BEFORE:-<none>}"

echo "▸ building + uploading (fastlane beta) — real exit code, no pipe…"
if ! ( cd ios && fastlane beta ); then
  echo "❌ fastlane beta FAILED — nothing uploaded. Do NOT report a release."
  exit 1
fi

echo "▸ fastlane says uploaded. Confirming with Apple (upload ≠ live — it processes)…"
for i in $(seq 1 20); do
  AFTER="$($ASC | head -1 || true)"
  if [ -n "$AFTER" ] && [ "$AFTER" != "$BEFORE" ]; then
    echo "✅ CONFIRMED on TestFlight by App Store Connect:"
    echo "    $AFTER"
    exit 0
  fi
  sleep 60
done

echo "⚠️  Uploaded, but Apple has NOT shown a new build after ~20 min."
echo "    Do NOT tell the user it's live yet — check App Store Connect / re-run the poll."
exit 1
