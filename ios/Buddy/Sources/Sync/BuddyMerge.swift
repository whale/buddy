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
    var erasedAt: Double?
    var savedAt: Double
    // Unknown top-level wire fields (the Mac's doneWordBag/pinned/restartStash and any
    // future peer's additions) — pass through merge/adopt/persist untouched.
    var extras: [String: JSONValue] = [:]
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
        let tombstones = mergeTombstones(va.tombstones, vb.tombstones)

        var today: TodayState?
        var carryHistory: [Day] = []
        if let ta = va.today, let tb = vb.today, ta.date == tb.date {
            let newerT = newer.today!, olderT = older.today!
            today = TodayState(
                date: ta.date,
                items: clampActiveItems(mergeItems(newerT.items, olderT.items, tombstones)),
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
                   CanonicalJSON.compare(oldLive.date, today!.date) < 0,
                   let rec = todayToHistoryRecord(oldLive) {
                    carryHistory.append(rec)
                }
            } else {
                today = va.today ?? vb.today
            }
        }

        // Deferred: union keyed by id, conflicts resolved by per-row v (send/unsend bump it).
        var deferred = mergeDeferred(newer.deferred, older.deferred, tombstones)
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

        return SyncSnapshot(
            today: today,
            history: mergeHistory(va.history + carryHistory, vb.history),
            deferred: deferred,
            settings: newer.settings ?? older.settings,
            tombstones: tombstones,
            erasedAt: erasedAt,
            savedAt: max(a.savedAt, b.savedAt),
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

    /// After a cross-device merge the UNION of both devices' active tasks can exceed the
    /// 6-task cap and carry same-title duplicates (each device minted its own id, so
    /// `mergeItems` keeps both). `hardCap` is only enforced on manual Add, never on merge —
    /// so re-clamp here: keep every done item, drop same-title active dupes, cap active tasks
    /// at `hardCap`. Order preserved (primary = newer save first → newer device's dup wins).
    /// Deterministic → both devices converge on the same clamped list, no ping-pong.
    /// Mirrors the Mac's `clampActiveItems` in dist/index.html.
    static func clampActiveItems(_ items: [BuddyTask]) -> [BuddyTask] {
        var seenTitles = Set<String>()
        var active = 0
        var out = [BuddyTask]()
        for it in items {
            if it.isDone { out.append(it); continue }   // done work never counts against the cap
            let title = it.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !title.isEmpty && seenTitles.contains(title) { continue }   // same-title dup → drop
            if active >= BuddyStore.hardCap { continue }                   // past the cap → drop overflow
            if !title.isEmpty { seenTitles.insert(title) }
            active += 1
            out.append(it)
        }
        return out
    }

    static func mergeItems(_ primary: [BuddyTask], _ secondary: [BuddyTask],
                           _ tombstones: [String: Double]) -> [BuddyTask] {
        var sec = [String: BuddyTask]()
        for i in secondary { sec[i.id] = i }
        var seen = Set<String>()
        var out = [BuddyTask]()
        for it in primary {                 // primary = newer save → keeps its order
            seen.insert(it.id)
            if tombstones[it.id] != nil { continue }
            if let other = sec[it.id] { out.append(pickItem(it, other)) } else { out.append(it) }
        }
        for it in secondary {               // items only on the older save → keep, don't lose
            if seen.contains(it.id) { continue }
            if tombstones[it.id] != nil { continue }
            out.append(it)
        }
        return out
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
                DayItem(id: "h-\(t.date)-\(i)", text: it.text, done: it.state == .done)
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

    /// Natural sort key for the positional per-day ids (h-<date>-<i>) so merged records
    /// keep planner order even past index 9; foreign ids sort lexicographically after.
    /// Mirrors the Mac's histIdKey (regex ^h-(.+)-(\d+)$ — greedy, so the LAST hyphen
    /// group is the numeric index).
    static func histIdKey(_ id: String) -> (d: String, i: Int, raw: String?) {
        if id.hasPrefix("h-"), let lastDash = id.lastIndex(of: "-"), lastDash > id.index(id.startIndex, offsetBy: 1) {
            let digits = id[id.index(after: lastDash)...]
            let mid = id[id.index(id.startIndex, offsetBy: 2)..<lastDash]
            if !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), !mid.isEmpty {
                return (d: String(mid), i: Int(digits) ?? 0, raw: nil)
            }
        }
        return (d: "", i: 0, raw: id)
    }
    static func histIdCompare(_ a: String, _ b: String) -> Int {
        let ka = histIdKey(a), kb = histIdKey(b)
        if ka.raw != nil || kb.raw != nil {
            return CanonicalJSON.compare(ka.raw ?? "", kb.raw ?? "")
        }
        if ka.d != kb.d { return CanonicalJSON.compare(ka.d, kb.d) }
        return ka.i == kb.i ? 0 : (ka.i < kb.i ? -1 : 1)
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
            byId[it.id] = DayItem(id: base.id, text: base.text, done: done)
        }
        let wx = x.weekday, wy = y.weekday
        let weekday = (!wx.isEmpty && !wy.isEmpty)
            ? (CanonicalJSON.lessOrEqual(wx, wy) ? wx : wy)
            : (wx.isEmpty ? wy : wx)
        // Stable sort (JS Array.sort is stable) — an equal-key pair keeps first-seen order.
        let items = order.compactMap { byId[$0] }.enumerated()
            .sorted { l, r in
                let c = histIdCompare(l.element.id, r.element.id)
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
        return c
    }
}
