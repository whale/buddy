import Foundation

// MARK: - BuddyMerge (sync step 3)
// Pure, field-level merge of two state snapshots — the Swift mirror of the Mac
// web app's merge() in dist/index.html. The adversarial review killed whole-doc
// last-write-wins (it silently drops one device's edits on any two-device day);
// this is the field-level replacement that loses NOTHING.
//
// merge(a, b) is PURE: it reads its inputs and returns a fresh value, mutating
// neither. Either side may be nil (fresh boot / unreadable store).
//
// Rules (identical to the Mac):
//   - tombstones  → union, latest deletedAt per id. A deleted id is never resurrected.
//   - erasedAt    → latest erase-all wins and acts as a BARRIER: any snapshot saved
//                   BEFORE that erase is "pre-erase" and its items/history are void.
//   - today items → keyed by id; higher per-item v wins (v rises on every edit), tie
//                   broken by the more-recent doneAt. Tombstoned ids dropped. The
//                   newer save's item order is preserved.
//   - history     → union by date; same-date records merge with done-wins.
//   - deferred    → union by id, tombstoned ids dropped.
//   - settings / today.date → the newer save wins (scalars).
//
// NOTE (step 4): timestamps are compared directly, which is correct WITHIN one
// device. Cross-device merge must first normalize UNITS — the Mac stores epoch
// MILLISECONDS, Swift's Date.timeIntervalSince1970 is SECONDS. Normalize before
// wiring this to the network (pull/push). See IOS-COMPANION-PLAN.md.
//
// Known model gap vs the Mac: the Mac's history items carry stable ids
// (h-<date>-<i>) and merge by id; iOS's DayItem is {text, done} with no id, so
// same-date history records merge positionally with done-wins. Stable per-day
// archival produces identical item order on both devices, so this is equivalent
// in practice — but DayItem should gain an id for fully robust history merge.

/// The mergeable subset of the persisted blob. Holds exactly the fields merge()
/// reasons about, so callers (boot reconcile, future sync pull/push) build one
/// from their store and apply the result back.
struct SyncSnapshot {
    var today: TodayState?
    var history: [Day]
    var deferred: [DeferredTask]
    var settings: BuddySettings?
    var tombstones: [String: Double]
    var erasedAt: Double?
    var savedAt: Double
}

enum BuddyMerge {

    static func merge(_ a: SyncSnapshot?, _ b: SyncSnapshot?) -> SyncSnapshot? {
        guard let a = a else { return b }
        guard let b = b else { return a }

        let erasedAt = latest(a.erasedAt, b.erasedAt)
        let va = (erasedAt != nil && a.savedAt < erasedAt!) ? voidPreErase(a) : a
        let vb = (erasedAt != nil && b.savedAt < erasedAt!) ? voidPreErase(b) : b

        let newerIsA = va.savedAt >= vb.savedAt
        let newer = newerIsA ? va : vb
        let older = newerIsA ? vb : va
        let tombstones = mergeTombstones(va.tombstones, vb.tombstones)

        let today: TodayState?
        if let ta = va.today, let tb = vb.today, ta.date == tb.date {
            today = TodayState(
                date: ta.date,
                items: mergeItems(newer.today?.items ?? [], older.today?.items ?? [], tombstones),
                morningDone: ta.morningDone || tb.morningDone     // OR-wins, mirrors the Mac
            )
        } else {
            today = newer.today ?? older.today      // different/missing days → newer day wins whole
        }

        return SyncSnapshot(
            today: today,
            history: mergeHistory(va.history, vb.history),
            deferred: mergeDeferred(va.deferred, vb.deferred, tombstones),
            settings: newer.settings ?? older.settings,
            tombstones: tombstones,
            erasedAt: erasedAt,
            savedAt: max(a.savedAt, b.savedAt)
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

    /// The surviving version of one today-item present on both sides.
    static func pickItem(_ x: BuddyTask, _ y: BuddyTask) -> BuddyTask {
        if y.v > x.v { return y }
        if x.v > y.v { return x }
        let dx = x.doneAt?.timeIntervalSince1970 ?? 0
        let dy = y.doneAt?.timeIntervalSince1970 ?? 0
        return dy > dx ? y : x          // tie on v → newer completion wins, else keep x
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

    static func mergeHistRecord(_ x: Day, _ y: Day) -> Day {
        // Union by item id (matches the Mac), done-wins. x's order is kept; y-only items appended.
        var byId = [String: DayItem]()
        for it in y.items { byId[it.id] = it }
        var seen = Set<String>()
        var items = [DayItem]()
        for it in x.items {
            seen.insert(it.id)
            if let o = byId[it.id] {
                items.append(DayItem(id: it.id, text: it.text, done: it.done || o.done))   // done-wins
            } else {
                items.append(it)
            }
        }
        for it in y.items where !seen.contains(it.id) { items.append(it) }
        return Day(date: x.date, weekday: x.weekday.isEmpty ? y.weekday : x.weekday, items: items)
    }

    static func mergeHistory(_ a: [Day], _ b: [Day]) -> [Day] {
        var byDate = [String: Day]()
        for rec in a + b {
            if let prev = byDate[rec.date] { byDate[rec.date] = mergeHistRecord(prev, rec) }
            else { byDate[rec.date] = rec }
        }
        return byDate.values.sorted { $0.date > $1.date }    // newest first (insert-at-0 order)
    }

    static func mergeDeferred(_ a: [DeferredTask], _ b: [DeferredTask],
                              _ tombstones: [String: Double]) -> [DeferredTask] {
        var byId = [String: DeferredTask]()
        var order = [String]()
        for d in a + b {
            if tombstones[d.id] != nil { continue }
            if byId[d.id] == nil { order.append(d.id) }
            byId[d.id] = d
        }
        return order.map { byId[$0]! }
    }

    /// A snapshot saved before the latest erase-all → its items/history are void.
    static func voidPreErase(_ s: SyncSnapshot) -> SyncSnapshot {
        var c = s
        if let t = c.today { c.today = TodayState(date: t.date, items: []) }
        c.history = []
        c.deferred = []
        return c
    }
}
