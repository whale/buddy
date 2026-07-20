# Buddy — Sync Compatibility

How Buddy keeps Mac and iOS in sync **when either platform updates on its own
schedule**. Mac auto-updates in minutes; iOS lags days behind App Store review.
Version skew between the two devices is therefore **permanent and normal** — the
sync design has to assume it, not hope to avoid it.

> **Status: IMPLEMENTED (wire-2) + verified.** The cleartext AAD envelope,
> refuse-to-clobber, and legacy upgrade all ship on Mac (`dist/index.html`) and
> iOS (`ios/.../Sync`), pinned by a shared envelope vector. Run `pnpm
> sync:validate` for a one-command PASS/FAIL across Mac logic + Mac↔iOS interop;
> full procedure in [`VALIDATION.md`](VALIDATION.md). The server wire floor
> (`supabase/migrations/20260719130000_buddy_wire_floor_fix.sql`) is written but ships DISABLED —
> raise it only after the wire-2 build saturates (see below).

This doc exists because it already bit us: a phone stuck on **v0.1.0**
(pre-encryption) next to a Mac on **v0.4.15** (encrypted). The Mac showed
"iPhone linked / Synced" and kept polling happily; the phone showed "Not
connected" and a totally different list. Silent split-brain, no warning, and —
worse — the encrypted client was actively **overwriting** the plaintext row the
old client still needed. See the incident post-mortem at the bottom.

---

## The one rule

> **Put a small, cleartext, tamper-proof header on every synced row — protocol
> version + crypto suite + minimum-reader version — so any client (even the
> server) can decide "I can't safely touch this" and _degrade_ instead of
> silently corrupting.**

Encrypt the *content*. Never encrypt the *routing label*. This is what
1Password (unencrypted KDF/format header outside the vault), Signal (cleartext
version byte on the envelope), and `age`/PASETO (versioned header, versioned
refusal) all do. Buddy currently encrypts its own version marker **inside** the
ciphertext, which is why the server — the one chokepoint both devices transit —
is blind to it and can enforce nothing.

Everything below is downstream of that header existing.

---

## Three versions, three axes — never one integer

Buddy today welds everything onto a single `version:1` that never changes. These
evolve on different clocks and must be **independent**:

| Axis | What it describes | Changes when |
|------|-------------------|--------------|
| `wire` | Envelope framing — how a row is packed/CAS'd | Envelope shape changes |
| `crypto` | Cipher + KDF suite (`aes256gcm.hkdf.v1`) | New cipher/KDF params |
| `schema` | Shape of `today` / `items` / `history` (what `migrate()` reads) | Data model changes |

The encryption flip in v0.4.0 was a **wire + crypto** change shipped with
`schema` still at `1` on both sides — so nothing could detect it. Splitting the
axes means a future crypto change can never again hide inside a data-version
field.

---

## The bootstrapping truth (why "just show a warning" wasn't enough)

**You cannot ship a message into a binary that already shipped.** The v0.1.0
iPhone has no mismatch-detection code and never will — it's frozen. Any
compatibility scheme only ever works *forward*, from the first version that
carries it. That has two hard consequences:

1. **The header should have shipped in v1.** It didn't, so there is a permanent
   tail of pre-header clients we can only handle by **not breaking them** or by
   **refusing their writes at the server** — never by messaging them.
2. **For everyone from v-next onward**, the header is the thing that makes
   graceful degradation possible. Ship it now; it's the floor under every future
   change.

---

## Degrade, never wall

Three states, not two. A "please update" modal can **brick a user who cannot
update** (paused Apple ID, managed device, App Store review still holding the
fix), and must never gate the local, already-working list.

1. **Compatible** — sync normally.
2. **Peer ahead, still readable** — sync, but a quiet non-blocking notice: "One
   device is on a newer version; some new things may not sync yet."
3. **Incompatible** — **stop syncing, keep working locally**, show a non-blocking
   notice **on both sides**, and **preserve both sides' data** for later merge.
   Never a blocking wall. Never let the local list stop working.

---

## Writes are the corruptor, not just reads

The nastiest part of the incident wasn't a stall — it was **active mutual
corruption**. A new (encrypted) client pulls the old client's plaintext row,
merges, then CAS-writes it back **encrypted**. The old client can no longer read
it. If the old client ever wins a CAS race it clobbers it back to plaintext. The
row ping-pongs between formats forever.

**Rule:** a client that detects it's sharing a CAS key with an older-format peer
must either **dual-write the old format** or enter **refuse-to-clobber** — never
silently upgrade the row out from under the peer. Compatibility gates **writes**,
not just reads.

---

## Tombstone GC across version skew = silent deletes or resurrection

Buddy's merge is "tombstones-for-everything." If a newer client garbage-collects
a tombstone (to bound blob growth) that a slower, days-behind iOS client hasn't
seen, the old client re-proposes the deleted item and it **resurrects** — the
classic CRDT tombstone-GC hazard.

**Rule:** never GC a tombstone until **every known bucket participant's
last-seen watermark is past it**. Devices don't record last-seen watermarks
today, so until they do: **don't GC tombstones at all.** A storage leak is
recoverable; a silent delete is not.

---

## Readers before writers (staged rollout)

Mac and iOS **never arrive at the same time** even when you press the button
together — Mac is live in minutes, iOS waits on review. So a breaking format
change ships in two waves:

1. Release the version that can **read** the new format to **both** platforms.
   Let it saturate (telemetry-gated — see below).
2. Only then release the version that **writes** the new format.

Never same-day both-platforms for a `wire`/`crypto` change.

---

## Threat boundary (honest-but-curious server)

The AAD binding stops a **downgrade within the encrypted format** (you can't move a
wire-1 ct into the wire-2 path or forge a header — GCM fails closed both ways) and
the server can't read content. But because clients still **read legacy plaintext**
(to migrate old rows), a fully hostile server could replace a row with *forged
plaintext* and a client would merge it — a data-integrity (not confidentiality)
attack, and only over task text. This is inherent to supporting the legacy tail;
the **server wire floor** (once raised) closes it by refusing sub-wire-2 writes.
For a personal, single-tenant backend this residual is acceptable; documented here
so it's a decision, not a surprise.

## Enforce the floor where both clients actually meet: the server

The client-side floor is useless against a frozen old client. The **only**
enforceable chokepoint is the Supabase CAS store — and it can only act once the
version marker is **cleartext** (per the one rule). Then a CAS RPC can reject
pushes whose `wire < floor`, and the floor is raised only after the readers-first
wave saturates. This is the single lever that reaches the permanent old-client
tail.

---

## Envelope schema

The wire row the CAS store holds as its opaque blob. Header is **cleartext** so
any reader can triage; header is bound as **AES-GCM AAD** so it can't be
tampered or downgraded. Only the content is encrypted.

```jsonc
{
  "b": "buddy",                    // magic — cheap "is this ours" check
  "wire": 2,                       // PROTOCOL/framing version of THIS envelope
                                   //   (absence of header === wire 1, legacy raw blob)
  "crypto": "aes256gcm.hkdf.v1",   // cipher+KDF suite id. New params ⇒ new id.
  "minReader": 2,                  // lowest wire version that can SAFELY read this row.
                                   //   maxWire < minReader ⇒ degrade + refuse-to-clobber,
                                   //   NEVER silent no-op, NEVER overwrite.
  "writer": { "app": "0.4.15", "plat": "mac" },  // cleartext HINTS for diagnostics only;
                                   //   never branch merge/security on these.
  "iv": "…base64…",                // AES-GCM IV
  "ct": "…base64…"                 // ciphertext of the data blob below.
                                   //   AAD = canonical-JSON of {b,wire,crypto,minReader}
}
```

Inside `ct`, after decrypt, the data blob carries its **own** independent
version:

```jsonc
{
  "schema": 1,                     // DATA-schema version — what migrate() switches on.
  "savedAt": 0,
  "today": { }, "history": [ ], "deferred": [ ], "tombstones": { },
  "syncNotice": { "combined": 9, "moved": 3, "dismissed": false },
                                   // KNOWN_WIRE_KEY. The "N tasks moved to Future on sync"
                                   //   banner: merged via pickNotice, part of blobContentKey
                                   //   (so a dismiss syncs). Normal mergeable app state.
  "unlinkedAt": 0                  // RESERVED transport marker (mutual unlink). Read RAW in
                                   //   syncOnce BEFORE any merge → bail as `unlinked`; NEVER
                                   //   merged or adopted. In Mac's DROP_WIRE_KEYS so it can't
                                   //   ride `extras` into local state (a leak = a permanent
                                   //   self-unlink loop). iOS merge() omits it from output. It
                                   //   is INSIDE the ciphertext (GCM-authenticated) — the
                                   //   server can't forge it, only replay/withhold the whole row.
  // unknown top-level keys still spread through (the additive KNOWN_WIRE_KEYS rule)
}
```

**Reserved keys, do not repurpose:** `unlinkedAt` (mutual-unlink signal) must never be
merged or added to `KNOWN_WIRE_KEYS`; a future wire change touching the data blob must
keep it a read-raw-then-bail marker. `syncNotice` is a normal merged key.

**Why each piece:** cleartext header ⇒ triage before decrypt works even with no
key (and the server can enforce a floor); AAD ⇒ no downgrade attack; `minReader`
is the actual degrade/refuse primitive; `wire:1 === no header` is how the legacy
plaintext tail is handled gracefully instead of clobbered.

**Honest limit:** this header only helps clients **from the version that
introduces it onward**. The frozen v0.1.0 tail is handled only by server-side
write rejection + the QR re-pair / force-update path.

---

## Post-mortem — the incident that started this (2026-07-18)

- Mac on v0.4.15 (encrypted), iPhone on v0.1.0 (pre-encryption), never on the
  same bucket. Mac Settings: "iPhone linked / Synced 19:50 · 1af578", polling
  every 2s, all no-ops. iPhone Settings: "Not connected", 0.1.0, its own list.
- Root causes: (1) phone never updated — TestFlight doesn't auto-update;
  (2) no protocol version outside the ciphertext, so no client and not the
  server could detect the mismatch; (3) the encrypted client silently overwrote
  the plaintext row (the corruptor above); (4) no degraded state — the Mac
  reported "linked" while nothing could actually converge.
- The fixes are this doc's rules. Highest-severity first: the **cleartext
  header** and the **CAS write-gating**. See the checklist in
  `RELEASE-CHECKLIST.md § Sync change gate`.
