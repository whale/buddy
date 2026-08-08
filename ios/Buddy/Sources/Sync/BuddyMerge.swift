import Foundation

// MARK: - BuddyMerge (sync Slice 2)
// Pure, field-level, fully DETERMINISTIC merge of two state snapshots — the Swift
// mirror of the Mac web app's merge() in dist/index.html. merge(a, b) must EQUAL
// merge(b, a): each conflict falls through to a content compare over the PROJECTED
// wire form (the fields both platforms share), so Mac and iPhone always pick the
// same winner and converge. Asymmetry here is exactly the 0.3.17 bug: each device
// "wins" locally, "Sent to today!" flashes then reverts, and edits overwrite.
//
// merge(a, b) is PURE: it reads its inputs and returns a fresh value, mutating
// neither. Either side may be nil (fresh boot / unreadable store).
//
// Rules (identical to the Mac):
//   - tombstones  → union, latest deletedAt per id. A deleted id is never resurrected.
//   - erasedAt    → latest erase-all wins and acts as a BARRIER: any snapshot saved
//                   BEFORE that erase is "pre-erase" and its items/history are void.
//   - "newer"     → higher savedAt (= last USER mutation, not serialize time); a tie
//                   falls through to a contentKey compare so both devices agree.
//   - today items → keyed by id; higher per-item v wins, tie → later doneAt, full tie
//                   → canonical content order. Tombstoned ids dropped. Newer order kept.
//   - today days  → same date: items merged + clamped, morningDone OR-wins. DIFFERENT
//                   dates: the CALENDAR-later date is live (a device suspended overnight
//                   can have the fresher savedAt but yesterday's date); the earlier-dated
//                   live list is archived into history, never dropped.
//   - history     → union by date; same-date records merge symmetrically (done-wins,
//                   text tie → canonical order, output sorted by natural id order).
//   - deferred    → union by id; per-row v (bumped on send/unsend) wins, tie → canonical
//                   order. A sent row whose Today copy didn't survive reconciles to plain.
//   - settings    → the newer save wins (scalars).
//   - extras      → union; newer's keys win. (restartStash/doneWordBag/pinned live here
//                   on iOS — they ride through untouched.)

/// The mergeable subset of the persisted blob. Holds exactly the fields merge()
/// reasons about, so callers (boot reconcile, sync pull/push) build one from their
/// store and apply the result back. Timestamps are SECONDS (converted to the Mac's
/// milliseconds at the wire boundary — see SyncWire).
struct SyncSnapshot {
    var today: TodayState?
    var history: [Day]
    var deferred: [DeferredTask]
    var settings: BuddySettings?
    var tombstones: [String: Double]
    /// id → the item's VERSION when a day-rollover archived it as done (plus when, in ms).
    /// A rollover DROPS completed rows, and pure absence never wins a union-merge — so the
    /// peer that never saw the completion just re-added its own ACTIVE copy and the task came
    /// back from the dead (field report 2026-08-08). This is the missing "it left today, on
    /// purpose" signal. Version-aware so a later undo (which bumps v past the mark) still wins.
    var doneTombs: [String: DoneMark] = [:]
    var erasedAt: Double?
    var savedAt: Double
    // A sync moved N over-cap tasks to Future — a dismissible, SYNCED notice (mirrors the
    // Mac's state.syncNotice). Nil when nothing was moved / it was dismissed on both sides.
    var syncNotice: SyncNotice? = nil
    // Mutual-unlink marker (seconds): a device stamps the shared bucket to dissolve the link so
    // the peer self-unlinks. Read BEFORE any merge (syncOnce), never merged into task data.
    var unlinkedAt: Double? = nil
    // Unknown top-level wire fields (the Mac's doneWordBag/pinned/restartStash and any
    // future peer's additions) — pass through merge/adopt/persist untouched.
    var extras: [String: JSONValue] = [:]
}

/// A "this id left Today because it was completed" marker: the item's version at archive
/// time, plus when. Byte-parallel to the Mac's `{v, t}`.
///
/// `t` is epoch MILLISECONDS on BOTH platforms and gets NO seconds↔ms conversion at the wire
/// boundary — unlike `tombstones`, which the Mac writes in ms and iOS writes in seconds. That
/// unit skew is why doneTombs is age-pruned and tombstones are not: an age check would read
/// every iPhone-minted tombstone as 1970 and delete it. Keep this field in ms. (Pinned by
/// BuddyMergeTests + the Mac's mergeTest.)
struct DoneMark: Codable, Equatable {
    var v: Int
    var t: Double

    init(v: Int, t: Double) { self.v = Swift.max(1, v); self.t = t }

    enum CodingKeys: String, CodingKey { case v, t }

    /// Fails CLOSED, exactly like the Mac's sanitizeDoneTombs: anything that is not a usable
    /// mark THROWS, and the map decoder below drops that entry. Failing open here would be the
    /// worst possible bug — a junk value would become `v:1`, which vetoes any item at v:1, i.e.
    /// a task you just typed, and `t:0` means it is never pruned. (Skeptic, 2026-08-08: the
    /// first version of this accepted null, {}, [1,2], v:0, v:-2 and even a string.)
    init(from decoder: Decoder) throws {
        struct Invalid: Error {}
        if let c = try? decoder.container(keyedBy: CodingKeys.self), let raw = try? c.decodeIfPresent(Int.self, forKey: .v) {
            guard raw > 0 else { throw Invalid() }
            self.v = raw
            let ts = (try? c.decodeIfPresent(Double.self, forKey: .t)) ?? 0
            self.t = ts > 0 ? ts : 0          // mirror the Mac: only a POSITIVE t counts
            return
        }
        // A bare number (a peer that wrote only the version). Must be a genuine JSON integer.
        let single = try decoder.singleValueContainer()
        guard let n = try? single.decode(Int.self), n > 0 else { throw Invalid() }
        self.v = n
        self.t = 0
    }
}

/// The "N tasks moved to Future on sync" banner state — synced so a dismiss on one device
/// clears it on the other. Byte-parallel to the Mac's `{combined,moved,dismissed}`.
struct SyncNotice: Codable, Equatable {
    var combined: Int
    var moved: Int
    var dismissed: Bool
    /// Integers ≥0, and nil when nothing was moved — the same rule the Mac's sanitizeNotice uses.
    static func sanitized(_ n: SyncNotice?) -> SyncNotice? {
        guard let n = n else { return nil }
        let moved = Swift.max(0, n.moved)
        if moved <= 0 { return nil }
        return SyncNotice(combined: Swift.max(moved, n.combined), moved: moved, dismissed: n.dismissed)
    }
}

enum BuddyMerge {

    static func merge(_ a: SyncSnapshot?, _ b: SyncSnapshot?) -> SyncSnapshot? {
        guard let a = a else { return b }
        guard let b = b else { return a }

        let erasedAt = latest(a.erasedAt, b.erasedAt)
        let va = (erasedAt != nil && a.savedAt < erasedAt!) ? voidPreErase(a) : a
        let vb = (erasedAt != nil && b.savedAt < erasedAt!) ? voidPreErase(b) : b

        // "Newer" = the side the USER last touched. Ties fall through to a content
        // compare so BOTH devices agree who's newer (merge must be symmetric).
        let newerIsA: Bool
        if va.savedAt != vb.savedAt {
            newerIsA = va.savedAt > vb.savedAt
        } else {
            newerIsA = CanonicalJSON.compare(BuddySync.contentKey(va), BuddySync.contentKey(vb)) >= 0
        }
        let newer = newerIsA ? va : vb
        let older = newerIsA ? vb : va
        var tombstones = mergeTombstones(va.tombstones, vb.tombstones)
        var doneTombs = mergeDoneTombs(va.doneTombs, vb.doneTombs)

        var today: TodayState?
        var carryHistory: [Day] = []
        var overflowItems: [BuddyTask] = []
        if let ta = va.today, let tb = vb.today, ta.date == tb.date {
            let newerT = newer.today!, olderT = older.today!
            let clamped = clampActive(mergeItems(newerT.items, olderT.items, tombstones, doneTombs))
            overflowItems = clamped.overflow
            today = TodayState(
                date: ta.date,
                items: clamped.kept,
                morningDone: ta.morningDone || tb.morningDone,     // OR-wins, mirrors the Mac
                extras: olderT.extras.merging(newerT.extras) { _, n in n }   // unknown today-level fields ride through
            )
        } else {
            // Different/missing days: the CALENDAR-LATER day is live (not the newer
            // save's — a device suspended overnight can have the fresher savedAt but
            // yesterday's date).
            if let ta = va.today, let tb = vb.today {
                let taWins = CanonicalJSON.compare(ta.date, tb.date) >= 0
                today = taWins ? ta : tb
                // Lossless daily merge: archive the earlier-dated live list instead of
                // dropping it (the Mac has this in merge() too — Swift previously didn't).
                let oldLive = taWins ? tb : ta
                if !oldLive.items.isEmpty, !oldLive.date.isEmpty,
                   CanonicalJSON.compare(oldLive.date, today!.date) < 0 {
                    if let rec = todayToHistoryRecord(oldLive) { carryHistory.append(rec) }
                    // ARCHIVING IS A ROLLOVER. The device that rolled first dropped its completed
                    // rows and marked them; this side is doing the same archive here, so it must
                    // emit the same marks — otherwise a task completed on the still-unrolled
                    // device comes back as the rolled device's stale ACTIVE copy (2026-08-08).
                    // Computed from inputs BOTH devices share, so it stays symmetric.
                    let stamp = dayStamp(oldLive.date)
                    var marks = [String: DoneMark]()
                    for it in oldLive.items where it.isDone && !it.id.isEmpty {
                        let m = DoneMark(v: Swift.max(1, it.v), t: stamp)
                        marks[it.id] = marks[it.id].map { $0.v >= m.v ? $0 : m } ?? m
                        // Pair every mark with a plain tombstone so an UN-UPDATED peer — which has
                        // never heard of doneTombs — still drops the row instead of re-adding it
                        // and push-fighting until the phone is updated. Stamped from the archived
                        // DAY, not the clock, so both devices emit byte-identical maps.
                        if tombstones[it.id] == nil { tombstones[it.id] = stamp }
                    }
                    doneTombs = mergeDoneTombs(doneTombs, marks)
                }
            } else {
                today = va.today ?? vb.today
            }
            // This branch used to take the later day's list WHOLESALE — no tombstone filter, no
            // done-marks — so a delete or a completion that landed while the peer had already
            // rolled was silently undone (skeptic, 2026-08-08). Apply the same gates the
            // same-date branch does.
            if today != nil {
                today!.items = today!.items.filter {
                    !$0.id.isEmpty && tombstones[$0.id] == nil && !doneMarked($0, doneTombs)
                }
            }
        }

        // Deferred: union keyed by id, conflicts resolved by per-row v (send/unsend bump it).
        var deferred = mergeDeferred(newer.deferred, older.deferred, tombstones)
        // Overflow relocation: active tasks that lost their slot in the cap fight get PARKED in
        // Future (wake:"" = undated) instead of deleted (whale 2026-07-19). Reuse the item's own
        // id so BOTH devices relocate the identical row; the invariant below keeps it out of
        // active. Byte-parallel to the Mac's merge().
        var movedCount = 0   // rows ACTUALLY relocated this merge — an overflow item already parked
                             // on the peer is skipped, so it must NOT inflate the notice's count.
        if !overflowItems.isEmpty {
            var have = Set(deferred.map { $0.id })
            for it in overflowItems where !it.id.isEmpty && tombstones[it.id] == nil && !have.contains(it.id) {
                deferred.append(DeferredTask(id: it.id, text: it.text, wake: "", v: it.v < 1 ? 1 : it.v))
                have.insert(it.id)
                movedCount += 1
            }
        }
        // INVARIANT — an id parked in Future is NOT also active. In the window where one device
        // has relocated an overflow row while the peer still holds it active, the union carries
        // it in BOTH lists; Future wins so it can't pop back onto the full list and re-overflow.
        if today != nil {
            let parked = Set(deferred.map { $0.id })
            today!.items = today!.items.filter { !parked.contains($0.id) }
        }
        // Reconcile "Sent to today!" rows whose linked Today copy did not survive the merge
        // (deduped, capped, or unsent-with-tombstone on the other device): a sent row without
        // its live counterpart is a lie — flip it back to a plain, sendable row. Runs LAST so
        // it is the final word on both devices → deterministic. (Does NOT bump v.)
        let liveIds = Set((today?.items ?? []).map { $0.id })
        deferred = deferred.map { d in
            if d.sent == true, d.sentTid == nil || !liveIds.contains(d.sentTid!) {
                var c = d; c.sent = nil; c.sentTid = nil
                return c
            }
            return d
        }
        // Same-TITLE dedupe for plain (un-sent) rows, AFTER the reconcile so a reconciled
        // orphan collapses into its twin: parking the same task on two devices mints two
        // ids for one intent, and an id-keyed union keeps both forever (field report:
        // 'Warren Logo' ×3). Deterministic winner: highest v, then stable content order.
        // Mirrors the Mac exactly; runs LAST so it is the final word on both devices.
        var bestByTitle = [String: DeferredTask]()
        for d in deferred where d.sent != true {
            let key = d.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if key.isEmpty { continue }
            if let p = bestByTitle[key] { bestByTitle[key] = pickDeferred(p, d) }
            else { bestByTitle[key] = d }
        }
        deferred = deferred.filter { d in
            if d.sent == true { return true }
            let key = d.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if key.isEmpty { return true }
            return bestByTitle[key]?.id == d.id
        }

        // Sync notice: only a merge that ACTUALLY relocated a task (movedCount>0) writes a fresh
        // notice; otherwise carry the peers' notice forward, keeping a dismiss sticky. Counts are
        // TRUTHFUL: keptActiveCount is read AFTER the invariant filter, moved = rows actually moved.
        // Both devices compute identical counts (same merged input) → converge. Mirrors the Mac.
        let keptActiveCount = (today?.items ?? []).filter { !$0.isDone }.count
        var syncNotice = pickNotice(va.syncNotice, vb.syncNotice)
        if movedCount > 0 {
            syncNotice = SyncNotice(combined: keptActiveCount + movedCount, moved: movedCount, dismissed: false)
        }

        return SyncSnapshot(
            today: today,
            history: mergeHistory(va.history + carryHistory, vb.history),
            deferred: deferred,
            settings: newer.settings ?? older.settings,
            tombstones: tombstones,
            doneTombs: pruneMarks(doneTombs),
            erasedAt: erasedAt,
            savedAt: max(a.savedAt, b.savedAt),
            syncNotice: SyncNotice.sanitized(syncNotice),
            extras: older.extras.merging(newer.extras) { _, n in n }   // union; newer wins per key
        )
    }

    // MARK: - helpers

    /// Latest of two optional timestamps; nil when neither is set (mirrors `||null`).
    static func latest(_ x: Double?, _ y: Double?) -> Double? {
        let m = Swift.max(x ?? 0, y ?? 0)
        return m > 0 ? m : nil
    }

    static func mergeTombstones(_ a: [String: Double], _ b: [String: Double]) -> [String: Double] {
        var out = a
        for (id, t) in b { out[id] = Swift.max(out[id] ?? 0, t) }
        return out
    }

    /// Decode one doneTombs map entry-by-entry so ONE malformed mark from a peer drops that
    /// entry instead of silently voiding the whole map (Codable's dictionary decode is all-or-
    /// nothing). Mirrors the Mac's sanitizeDoneTombs, which filters per key.
    static func sanitizeMarks(_ raw: [String: JSONValue]?) -> [String: DoneMark] {
        guard let raw = raw else { return [:] }
        var out = [String: DoneMark]()
        let enc = JSONEncoder(), dec = JSONDecoder()
        for (id, v) in raw where !id.isEmpty {
            guard let data = try? enc.encode(v), let m = try? dec.decode(DoneMark.self, from: data) else { continue }
            out[id] = m
        }
        return out
    }

    /// Union keeping the HIGHEST mark per id (v first, then t). Symmetric, like every other
    /// merge rule here. Mirrors the Mac's mergeDoneTombs.
    static func mergeDoneTombs(_ a: [String: DoneMark], _ b: [String: DoneMark]) -> [String: DoneMark] {
        var out = a
        for (id, m) in b {
            guard let p = out[id] else { out[id] = m; continue }
            out[id] = (m.v != p.v) ? (m.v > p.v ? m : p) : DoneMark(v: p.v, t: Swift.max(p.t, m.t))
        }
        return out
    }

    /// doneTombs is unioned forever and rides every push, and a rollover adds marks EVERY day —
    /// so it needs a ceiling. 90 days: a peer that stale can't converge on today's list anyway.
    /// A mark with no clock (t == 0) is KEPT — "no timestamp" is not "expired".
    /// Plain `tombstones` are deliberately NOT pruned here (see DoneMark's unit note).
    static let markRetention: Double = 90 * 86_400_000   // ms
    static func pruneMarks(_ marks: [String: DoneMark]) -> [String: DoneMark] {
        // Cutoff is relative to the NEWEST mark, NOT to Date(). Reading the clock inside merge()
        // makes eviction depend on WHEN you merged: two devices minutes apart disagree at the
        // boundary, each re-supplies the mark by union, and they push at each other until the
        // skew passes (forever, on a device with a wrong clock).
        let newest = marks.values.map { $0.t }.max() ?? 0
        let cutoff = newest - markRetention
        var out = [String: DoneMark]()
        for (id, m) in marks {
            if m.t > 0 && m.t < cutoff { continue }       // t == 0 means "no clock", never "expired"
            out[id] = m
        }
        return out
    }

    /// Midnight-UTC of a "YYYY-MM-DD" day, in ms. Marks are stamped from the ARCHIVED DAY, never
    /// from the local clock, so both devices emit byte-identical maps. Mirrors the Mac's dayStamp.
    static func dayStamp(_ date: String) -> Double {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        guard let d = f.date(from: date) else { return 0 }
        return d.timeIntervalSince1970 * 1000
    }

    /// Is this item superseded by a done-mark? Only when the mark is at or above the item's own
    /// version — an edit or undo after the archive raises v and escapes the mark.
    /// STRICTLY greater, not >=. At EQUAL v the two sides hold genuinely concurrent states and
    /// neither is newer — vetoing there annihilates a real edit with no tombstone, no history row
    /// and no trace (rename on the phone while the Mac archives it as done). The completing
    /// device always bumps v ABOVE the peer's stale copy, so `>` still catches every real case.
    static func doneMarked(_ it: BuddyTask, _ marks: [String: DoneMark]) -> Bool {
        guard let m = marks[it.id] else { return false }
        return m.v > Swift.max(1, it.v)
    }

    /// Was this id removed by a ROLLOVER rather than a user delete? A rollover writes BOTH a
    /// plain tombstone and a done-mark; a delete writes only the tombstone. The pairing is what
    /// lets an un-updated peer converge (it honours tombstones even though it has never heard of
    /// doneTombs), and the mark is what lets a later undo escape the otherwise-absolute veto.
    static func rollbackEscapes(_ it: BuddyTask, _ marks: [String: DoneMark]) -> Bool {
        guard let m = marks[it.id] else { return false }
        return m.v < Swift.max(1, it.v)
    }

    /// The surviving version of one today-item present on both sides. FULLY
    /// deterministic: every tie falls through to a canonical compare of the PROJECTED
    /// wire form (the Mac's _ckItem — the fields both platforms share), so
    /// pick(x, y) == pick(y, x) on both devices.
    static func pickItem(_ x: BuddyTask, _ y: BuddyTask) -> BuddyTask {
        if x.v != y.v { return y.v > x.v ? y : x }            // higher v = more edits wins
        let dx = x.doneAt?.timeIntervalSince1970 ?? 0
        let dy = y.doneAt?.timeIntervalSince1970 ?? 0
        if dx != dy { return dy > dx ? y : x }                // tie on v → newer completion wins
        return CanonicalJSON.lessOrEqual(BuddySync.ckItem(x), BuddySync.ckItem(y)) ? x : y
    }

    /// Same idea for a deferred (Future) row present on both sides. Deferred rows carry
    /// their own `v` (bumped on send / unsend) — without it, "Sent to today!" set on one
    /// device lost to the other device's stale copy on the very next pass (the revert bug).
    static func pickDeferred(_ x: DeferredTask, _ y: DeferredTask) -> DeferredTask {
        if x.v != y.v { return y.v > x.v ? y : x }
        return CanonicalJSON.lessOrEqual(BuddySync.ckDef(x), BuddySync.ckDef(y)) ? x : y
    }

    /// Which device MINTED an id? Mac uses lowercase UUIDs; iOS uses UUID().uuidString, which
    /// is UPPERCASE. Any uppercase letter ⇒ iPhone-minted. Lets merge give Mac tasks slot
    /// priority when the union exceeds the cap — deterministically from the id, not "which
    /// device am I". Mirrors the Mac's `idIsIos`.
    /// Parity note: the Mac uses ASCII `/[A-Z]/`; this uses Unicode `.uppercaseLetters`. Every id
    /// the app mints is ASCII (UUID / `n<base36>` / `h-…`), so the two never disagree. Only a
    /// non-ASCII-uppercase id (e.g. Greek/Cyrillic) would diverge — not reachable, since ids are
    /// never user text. Keep them matched if id minting ever changes.
    static func idIsIos(_ id: String) -> Bool {
        id.rangeOfCharacter(from: .uppercaseLetters) != nil
    }

    /// After a cross-device merge the UNION of both devices' active tasks can exceed the
    /// 6-task cap and carry same-title dupes (each device minted its own id). Returns
    /// (kept, overflow): done items always kept; same-title dupes dropped; active over the cap
    /// become OVERFLOW — the caller relocates these to Future instead of DELETING them, so a
    /// task never silently vanishes on sync (whale 2026-07-19). Slot priority: Mac-minted
    /// (lowercase id) keeps its slot, iPhone-minted (uppercase id) overflows first, last-first
    /// within a device. Deterministic on the SAME merged input → both devices converge.
    /// Byte-parallel to the Mac's `clampActive`.
    static func clampActive(_ items: [BuddyTask]) -> (kept: [BuddyTask], overflow: [BuddyTask]) {
        var seenTitles = Set<String>()
        var activeIdx = [Int]()
        var dropDup = Set<Int>()
        for (i, it) in items.enumerated() {
            if it.isDone { continue }                    // done handled below (always kept)
            let title = it.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !title.isEmpty && seenTitles.contains(title) { dropDup.insert(i); continue }
            if !title.isEmpty { seenTitles.insert(title) }
            activeIdx.append(i)
        }
        var overflowSet = Set<Int>()
        if activeIdx.count > BuddyStore.hardCap {
            var excess = activeIdx.count - BuddyStore.hardCap
            // iPhone-origin last-first, then (defensively) Mac-origin last-first.
            let ios = activeIdx.filter { idIsIos(items[$0].id) }.reversed()
            let mac = activeIdx.filter { !idIsIos(items[$0].id) }.reversed()
            for i in Array(ios) + Array(mac) {
                if excess <= 0 { break }
                overflowSet.insert(i); excess -= 1
            }
        }
        var kept = [BuddyTask](), overflow = [BuddyTask]()
        for (i, it) in items.enumerated() {
            if dropDup.contains(i) { continue }
            if overflowSet.contains(i) { overflow.append(it) } else { kept.append(it) }
        }
        return (kept, overflow)
    }

    /// Merge two sync notices → one. Deterministic + symmetric: higher (combined, then moved)
    /// count is the base; dismissed is sticky. Mirrors the Mac's `pickNotice`.
    static func pickNotice(_ a: SyncNotice?, _ b: SyncNotice?) -> SyncNotice? {
        guard let a = a else { return b }
        guard let b = b else { return a }
        let base: SyncNotice = a.combined != b.combined ? (a.combined > b.combined ? a : b)
            : (a.moved != b.moved ? (a.moved > b.moved ? a : b) : a)
        return SyncNotice(combined: base.combined, moved: base.moved, dismissed: a.dismissed || b.dismissed)
    }

    static func mergeItems(_ primary: [BuddyTask], _ secondary: [BuddyTask],
                           _ tombstones: [String: Double],
                           _ doneTombs: [String: DoneMark] = [:]) -> [BuddyTask] {
        var sec = [String: BuddyTask]()
        for i in secondary { sec[i.id] = i }
        var seen = Set<String>()
        var out = [BuddyTask]()
        // Resolve the winner FIRST, then judge it — an undo on the losing side raises v past the
        // mark and must come back. A plain tombstone stays an unconditional veto UNLESS a
        // done-mark identifies it as a rollover-archive tombstone this item has outlived.
        func gone(_ it: BuddyTask) -> Bool {
            if tombstones[it.id] != nil { return !rollbackEscapes(it, doneTombs) }
            return doneMarked(it, doneTombs)
        }
        for it in primary {                 // primary = newer save → keeps its order
            seen.insert(it.id)
            let win = sec[it.id].map { pickItem(it, $0) } ?? it
            if gone(win) { continue }
            out.append(win)
        }
        for it in secondary {               // items only on the older save → keep, don't lose
            if seen.contains(it.id) { continue }
            if gone(it) { continue }
            out.append(it)
        }
        // Drop stray EMPTY active items — a blank, untitled task carries no information
        // and must never survive a merge or ride the wire (that's how a phantom blank
        // reached a second device and falsely tripped lvl2, 2026-07-28). Done rows are
        // always kept. Mirrors the Mac mergeItems filter.
        return out.filter { $0.isDone || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - history

    /// Archive a live day as a history record — the Mac's todayToHistoryRecord.
    /// Stable positional ids (h-<date>-<i>) so two devices archiving the same day
    /// produce identical ids that merge() dedupes cleanly.
    static func todayToHistoryRecord(_ today: TodayState?) -> Day? {
        guard let t = today, !t.date.isEmpty, !t.items.isEmpty else { return nil }
        return Day(
            date: t.date, weekday: weekdayName(for: t.date),
            items: t.items.enumerated().map { i, it in
                // REAL item id (+ ord for planner order). See DayItem's note: the old
                // positional id merged two different tasks into one across devices.
                DayItem(id: it.id.isEmpty ? "h-\(t.date)-\(i)" : it.id,
                        text: it.text, done: it.state == .done, ord: i)
            }
        )
    }

    /// English day names, mirroring the Mac's DOW constant (locale-independent so both
    /// platforms archive the same weekday string for the same date).
    static let dow = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static func weekdayName(for dateString: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        guard let d = f.date(from: dateString) else { return "" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return dow[cal.component(.weekday, from: d) - 1]
    }

    /// Row order: explicit `ord`, else the index parsed out of a LEGACY positional id, else 0
    /// (DayItem.order). Id breaks ties so the ordering is total and identical on both platforms.
    /// Mirrors the Mac's histRowCompare.
    static func histRowCompare(_ a: DayItem, _ b: DayItem) -> Int {
        if a.order != b.order { return a.order < b.order ? -1 : 1 }
        return CanonicalJSON.compare(a.id, b.id)
    }

    /// Merge two same-date records SYMMETRICALLY: union by id, done-wins, text conflicts
    /// resolved by stable content order, output sorted by id (not by argument order).
    /// Mirrors the Mac's mergeHistRecord.
    static func mergeHistRecord(_ x: Day, _ y: Day) -> Day {
        var byId = [String: DayItem]()
        var order = [String]()
        let ck = { (h: DayItem) -> String in
            CanonicalJSON.canonical(.object(["id": .string(h.id), "text": .string(h.text), "done": .bool(h.done)]))
        }
        for it in x.items + y.items {
            guard !it.id.isEmpty else { continue }
            guard let p = byId[it.id] else { byId[it.id] = it; order.append(it.id); continue }
            let done = p.done || it.done                                   // done-wins
            let base = CanonicalJSON.lessOrEqual(ck(p), ck(it)) ? p : it   // stable text winner
            // Prefer a DEFINED ord over a fallback: `order` returns 0 for a row carrying no
            // ordering at all, and min() would let that zero permanently flatten a real order the
            // first time it met a copy stripped by an older peer.
            let ord: Int
            if let a = p.ord, let b = it.ord { ord = Swift.min(a, b) }
            else { ord = p.ord ?? it.ord ?? Swift.min(p.order, it.order) }
            byId[it.id] = DayItem(id: base.id, text: base.text, done: done, ord: ord)
        }
        let wx = x.weekday, wy = y.weekday
        let weekday = (!wx.isEmpty && !wy.isEmpty)
            ? (CanonicalJSON.lessOrEqual(wx, wy) ? wx : wy)
            : (wx.isEmpty ? wy : wx)
        // Stable sort (JS Array.sort is stable) — an equal-key pair keeps first-seen order.
        let items = order.compactMap { byId[$0] }.enumerated()
            .sorted { l, r in
                let c = histRowCompare(l.element, r.element)
                return c != 0 ? c < 0 : l.offset < r.offset
            }
            .map { $0.element }
        return Day(date: x.date, weekday: weekday, items: items)   // rebuilt fresh (mirrors the Mac)
    }

    static func mergeHistory(_ a: [Day], _ b: [Day]) -> [Day] {
        var byDate = [String: Day]()
        var order = [String]()
        for rec in a + b {
            guard !rec.date.isEmpty else { continue }
            if let prev = byDate[rec.date] { byDate[rec.date] = mergeHistRecord(prev, rec) }
            else { byDate[rec.date] = rec; order.append(rec.date) }
        }
        return order.compactMap { byDate[$0] }
            .sorted { CanonicalJSON.compare($0.date, $1.date) > 0 }    // newest first (unshift order)
    }

    /// Union by id with per-row conflict resolution (pickDeferred). Args are (newer, older)
    /// so first-seen order = the newer save's order — deterministic because both devices
    /// agree on who's newer.
    static func mergeDeferred(_ a: [DeferredTask], _ b: [DeferredTask],
                              _ tombstones: [String: Double]) -> [DeferredTask] {
        var byId = [String: DeferredTask]()
        var order = [String]()
        for d in a + b {
            if tombstones[d.id] != nil { continue }
            if let prev = byId[d.id] { byId[d.id] = pickDeferred(prev, d) }
            else { byId[d.id] = d; order.append(d.id) }
        }
        return order.compactMap { byId[$0] }
    }

    /// A snapshot saved before the latest erase-all → its items/history are void.
    /// NOTE: the Mac also nulls restartStash here; on iOS restartStash rides in the
    /// top-level extras bag, which is left alone. Acceptable asymmetry ONLY because the
    /// Mac is the sole writer of restartStash and voids it on its own side before pushing.
    static func voidPreErase(_ s: SyncSnapshot) -> SyncSnapshot {
        var c = s
        if var t = c.today { t.items = []; c.today = t }   // keep date/morningDone/extras (mirrors {...src.today, items:[]})
        c.history = []
        c.deferred = []
        c.syncNotice = nil
        return c
    }
}
