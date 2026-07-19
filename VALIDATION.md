# Buddy — Validating Sync Works Across Mac ↔ iOS

This is the runbook for answering, **independently and without a human holding a
phone**: *is Buddy's sync working, and is it safe when Mac and iOS are on
different versions?* Any agent can run these top to bottom. Companion:
[`SYNC-COMPAT.md`](SYNC-COMPAT.md) (the design), `RELEASE-CHECKLIST.md § Sync
change gate` (the per-PR gate).

The trust chain: **a shared envelope vector.** Mac (WebCrypto) and iOS
(CryptoKit) each encrypt the same fixed input and must produce the **same
ciphertext**:

```
dwuU613APPxtAVeAdb_UI1J97z3qrFHjfMMU
```

If both platforms emit that string, they provably read each other's wire rows.
Every check below leans on that.

---

## 1. One command — Mac logic + Mac↔iOS interop (start here)

```
pnpm sync:validate
```

Runs headless (Chromium + the Swift toolchain). **Expect `✅ PASS — 10/10`:**

- `Mac syncTest` 32/32 — merge / CAS / E2E correctness
- `Mac mergeTest` — lossless union
- `Mac skewTest GUARDS` 6/6 — the version-skew fix (see §what-it-proves)
- five named guards: backward read · writes wire-2 · refuse-to-clobber · AAD · legacy upgrade
- `Mac wire-2 envelope vector == shared pin`
- `iOS envelope parity (Swift CryptoKit == Mac WebCrypto)` — the interop linchpin

Exit code is non-zero on any failure. If the Swift line says `SKIPPED`, you're
not on macOS — run it on a Mac to get the interop proof.

**What the guards prove** (`__buddy.skewTest`, `dist/index.html`):

| Guard | Proves |
|-------|--------|
| backward read | a new client still reads an OLD plaintext row |
| writes a WIRE-2 envelope | new writes carry the cleartext `{b,wire,crypto,minReader}` header |
| refuse-to-clobber | a peer newer than we can read → **degrade, never overwrite** |
| AAD | tampering the cleartext header **fails decryption** (no downgrade) |
| legacy upgrade | a wire-1 `{enc:1}` row is read AND rewritten as wire-2 |

`skewTest` also reports **1 documented gap**: a *frozen* pre-header peer (the
v0.1.0 phone, raw, unchangeable) can still clobber a wire-2 row. The client
cannot reach it — only the **server wire floor** + a re-pair do. That's expected,
not a regression.

---

## 2. Full iOS suite (compiles the app + runs every unit test)

```
cd ios && xcodebuild test -project Buddy.xcodeproj -scheme Buddy \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BuddyTests
```

**Expect `TEST SUCCEEDED`.** The crypto/interop tests are in
`BlobCryptoTests` — `testWireV2EnvelopeVectorMatchesSharedPin` (the same vector
as §trust-chain), `testWireV2AADTamperThrows`, `testWireV2Detection`. To run just
those: append `/BlobCryptoTests`.

---

## 3. Two live devices converge (real backend, no phone)

```
pnpm sync:live
```

Boots two isolated browser "devices" ("mac" + "phone") paired on the real
Supabase backend with a throwaway syncKey, and drives future→today, undo,
dedupe, and convergence end-to-end. Needs creds in `.supabase-buddy.secret`
(gitignored). **Expect all specs green.** To reproduce a specific field report,
extend the spec with the exact steps before touching merge code.

---

## 4. The one human step — a real phone

Everything above runs without a device. The only thing an agent can't do is drive
a physical iPhone through a real update + QR re-pair. When a human is available:

1. On the phone: update Buddy from TestFlight to the wire-2 build (a pre-wire-2
   phone can't read the Mac's rows — it must be updated).
2. Phone → Settings → **Scan QR to pair**; Mac → Settings → **Resync** (shows the QR).
3. Add a task on each device → confirm it appears on the other within ~2s.
4. Confirm the bucket suffix matches on both (`Synced HH:MM · abc123`), and that
   neither shows **Update needed** (the degraded state).

---

## Enabling the server wire floor (after saturation)

The floor is the only thing that stops a *frozen* old client from clobbering. It
ships **disabled** (`wire_floor = 0`, a no-op). Once the wire-2 build has
saturated Mac + iOS (watch `buddy-events.jsonl` for `sync-peer-newer` /
pre-header writers going quiet, ≥14 days to cover App Store review):

```sql
select public.buddy_set_wire_floor(2);   -- reject sub-wire-2 writes
-- select public.buddy_set_wire_floor(0);   -- to disable again
```

Never raise it before saturation, or you lock out your own not-yet-updated
clients. Verify with `supabase/tests/buddy_wire_floor_test.sql`.

---

## If a check fails

`RELEASE-CHECKLIST.md § Sync change gate` is the per-PR discipline. The golden
rule (SYNC-COMPAT.md): the wire format is **additive-only**; any change to the
envelope framing or crypto is BREAKING and needs a new `wire` number,
dual-write, readers-before-writers rollout, and the floor raised only after
saturation.
