import Foundation

// MARK: - Task state mirrors the web app's state model
// Web source: dist/index.html → state.today.items[].state
// Values: "neutral" (default), "focused" (highlighted), "done"
enum TaskState: String, Codable {
    case neutral
    case focused
    case done
}

// MARK: - Single task item
// Mirrors: state.today.items[] in the web app
struct BuddyTask: Identifiable, Codable, Equatable {
    var id: String
    var text: String
    var state: TaskState
    var doneAt: Date?
    // Per-item version (merge tie-breaker), mirrors the Mac's item.v. Starts at 1 and
    // rises on any state/text change so merge() can pick the winning copy per id.
    var v: Int
    // Unknown fields from a newer peer (e.g. the Mac's `src`/`doneWord`, or future
    // additions) — captured at decode, re-emitted at encode. Version-skew safety.
    var extras: [String: JSONValue]

    // Convenience: "done" row shows struck-through text in inkDim colour
    var isDone: Bool { state == .done }
    // Convenience: active = pressing on you (not done)
    var isActive: Bool { state != .done }

    // Boss Mode (Mac parity): a completed task the user swept off the Today LIST via "Move to
    // done" — still lives in state (Done tab, rollover, sync see it), just hidden from Today.
    // Backed by the per-item `extras` bag (epoch MS, matching the Mac's `item.clearedAt`), so it
    // rides the existing wire with NO merge/contentKey change — an action on either device syncs.
    // (Excluded from `itemValue`/contentKey exactly like the Mac; the v-bump on set drives sync.)
    var clearedAt: Date? {
        get {
            switch extras["clearedAt"] {
            case .int(let ms)?:    return ms > 0 ? Date(timeIntervalSince1970: Double(ms) / 1000) : nil
            case .number(let ms)?: return ms > 0 ? Date(timeIntervalSince1970: ms / 1000) : nil
            default:               return nil
            }
        }
        set {
            if let d = newValue { extras["clearedAt"] = .int(Int64((d.timeIntervalSince1970 * 1000).rounded())) }
            else { extras["clearedAt"] = nil }
        }
    }
    var isCleared: Bool { clearedAt != nil }

    init(id: String, text: String, state: TaskState, doneAt: Date? = nil, v: Int = 1,
         extras: [String: JSONValue] = [:]) {
        self.id = id; self.text = text; self.state = state; self.doneAt = doneAt; self.v = v
        self.extras = extras
    }

    private static let knownKeys: Set<String> = ["id", "text", "state", "doneAt", "v"]
    enum CodingKeys: String, CodingKey { case id, text, state, doneAt, v }

    // Tolerant decode: blobs written before `v` existed default to version 1.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = try c.decode(String.self, forKey: .id)
        text  = (try? c.decode(String.self, forKey: .text)) ?? ""
        state = (try? c.decode(TaskState.self, forKey: .state)) ?? .neutral
        doneAt = try? c.decodeIfPresent(Date.self, forKey: .doneAt)
        v     = (try? c.decodeIfPresent(Int.self, forKey: .v)) ?? 1
        extras = decodeExtras(from: decoder, known: Self.knownKeys)
    }

    // Extras first, known keys after (known keys always win on a name clash).
    func encode(to encoder: Encoder) throws {
        var dyn = encoder.container(keyedBy: AnyCodingKey.self)
        for (k, val) in extras { try dyn.encode(val, forKey: AnyCodingKey(k)) }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(state, forKey: .state)
        try c.encodeIfPresent(doneAt, forKey: .doneAt)
        try c.encode(v, forKey: .v)
    }
}

// MARK: - A day in history
// Mirrors: state.history[] in the web app — flat {id, text, done} (not full TaskState).
// The id is the Mac's stable per-day key `h-<date>-<i>`, so two devices archiving the
// same day produce identical ids and merge() unions history by id (not by position).
struct DayItem: Codable {
    var id: String
    var text: String
    var done: Bool

    init(id: String, text: String, done: Bool) { self.id = id; self.text = text; self.done = done }

    enum CodingKeys: String, CodingKey { case id, text, done }

    // Tolerant decode: history records written before ids existed get a synthesized
    // positional id on load (the caller passes the date+index via a fallback id).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
        id   = (try? c.decode(String.self, forKey: .id)) ?? ""   // backfilled by Day.normalizedItems
    }
}

struct Day: Codable, Identifiable {
    // Use date as stable identity — one record per calendar day
    var id: String { date }
    var date: String    // "YYYY-MM-DD"
    var weekday: String // e.g. "Monday"
    var items: [DayItem]
    // Record-level unknown fields from a newer peer (version-skew safety).
    var extras: [String: JSONValue]

    init(date: String, weekday: String, items: [DayItem], extras: [String: JSONValue] = [:]) {
        self.date = date; self.weekday = weekday; self.items = items; self.extras = extras
    }

    private static let knownKeys: Set<String> = ["date", "weekday", "items"]
    enum CodingKeys: String, CodingKey { case date, weekday, items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date    = (try? c.decode(String.self, forKey: .date)) ?? ""
        weekday = (try? c.decode(String.self, forKey: .weekday)) ?? ""
        items   = (try? c.decode([DayItem].self, forKey: .items)) ?? []
        extras  = decodeExtras(from: decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        var dyn = encoder.container(keyedBy: AnyCodingKey.self)
        for (k, val) in extras { try dyn.encode(val, forKey: AnyCodingKey(k)) }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encode(weekday, forKey: .weekday)
        try c.encode(items, forKey: .items)
    }

    // Backfill missing item ids with the Mac's stable scheme `h-<date>-<i>` so legacy
    // records (saved before DayItem had an id) merge by id after this runs.
    mutating func backfillItemIds() {
        for i in items.indices where items[i].id.isEmpty {
            items[i].id = "h-\(date)-\(i)"
        }
    }
}

// MARK: - Today's state
// Mirrors: state.today in the web app ({date, items, morningDone}).
struct TodayState: Codable {
    var date: String        // "YYYY-MM-DD"
    var items: [BuddyTask]
    // Carried for sync fidelity with the Mac: whether today's planner was completed.
    // The Mac re-shows its morning screen when this is false, so it MUST survive a
    // cross-device merge (OR-wins). iOS has no morning screen yet — the field is inert
    // here but must round-trip so syncing with a phone never un-plans the Mac.
    var morningDone: Bool
    // Today-level unknown fields from a newer peer (version-skew safety).
    var extras: [String: JSONValue]

    init(date: String, items: [BuddyTask], morningDone: Bool = false,
         extras: [String: JSONValue] = [:]) {
        self.date = date; self.items = items; self.morningDone = morningDone; self.extras = extras
    }

    private static let knownKeys: Set<String> = ["date", "items", "morningDone"]
    enum CodingKeys: String, CodingKey { case date, items, morningDone }

    init(from d: Decoder) throws {       // tolerant: blobs saved before morningDone default to false
        let c = try d.container(keyedBy: CodingKeys.self)
        date  = (try? c.decode(String.self, forKey: .date)) ?? ""
        items = (try? c.decode([BuddyTask].self, forKey: .items)) ?? []
        morningDone = (try? c.decodeIfPresent(Bool.self, forKey: .morningDone)) ?? false
        extras = decodeExtras(from: d, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        var dyn = encoder.container(keyedBy: AnyCodingKey.self)
        for (k, val) in extras { try dyn.encode(val, forKey: AnyCodingKey(k)) }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encode(items, forKey: .items)
        try c.encode(morningDone, forKey: .morningDone)
    }
}

// MARK: - Deferred task model
// Mirrors the Mac's deferred[] shape: { id, text, wake, sent?, sentTid?, v }
// `v` is the per-row merge version: bumped on send (wake) AND unsend so the row that
// changed most recently wins a cross-device conflict deterministically — without it,
// "Sent to today!" set on one device lost to the other device's stale copy (the
// 0.3.17 revert bug).
struct DeferredTask: Codable, Identifiable {
    var id: String
    var text: String
    var wake: String  // "YYYY-MM-DD"
    var sent: Bool? = nil       // "Sent to today!" confirmation (omitted when not sent)
    var sentTid: String? = nil  // id of the Today copy this was sent to, for undo
    var v: Int = 1              // merge version — rises on send/unsend
    var extras: [String: JSONValue] = [:]

    init(id: String, text: String, wake: String, sent: Bool? = nil, sentTid: String? = nil,
         v: Int = 1, extras: [String: JSONValue] = [:]) {
        self.id = id; self.text = text; self.wake = wake
        self.sent = sent; self.sentTid = sentTid; self.v = v; self.extras = extras
    }

    private static let knownKeys: Set<String> = ["id", "text", "wake", "sent", "sentTid", "v"]
    enum CodingKeys: String, CodingKey { case id, text, wake, sent, sentTid, v }

    // Tolerant decode: rows written before `v` existed default to 1; a falsy `sent`
    // normalises to nil (the Mac's hydrate deletes sent/sentTid unless truthy).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id   = try c.decode(String.self, forKey: .id)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        wake = (try? c.decode(String.self, forKey: .wake)) ?? ""
        let s = (try? c.decodeIfPresent(Bool.self, forKey: .sent)) ?? nil
        if s == true {
            sent = true
            sentTid = (try? c.decodeIfPresent(String.self, forKey: .sentTid)) ?? nil
        } else {
            sent = nil; sentTid = nil
        }
        v = (try? c.decodeIfPresent(Int.self, forKey: .v)) ?? 1
        extras = decodeExtras(from: decoder, known: Self.knownKeys)
    }

    // Mirrors the Mac's serialize(): sent/sentTid only on the wire when actually sent.
    func encode(to encoder: Encoder) throws {
        var dyn = encoder.container(keyedBy: AnyCodingKey.self)
        for (k, val) in extras { try dyn.encode(val, forKey: AnyCodingKey(k)) }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(wake, forKey: .wake)
        if sent == true {
            try c.encode(true, forKey: .sent)
            try c.encodeIfPresent(sentTid, forKey: .sentTid)
        }
        try c.encode(v, forKey: .v)
    }
}

// MARK: - Full persisted state
// Mirrors the whole localStorage blob: { today, history, deferred, settings, tombstones, erasedAt }
struct BuddyState: Codable {
    var today: TodayState
    var history: [Day]
    var deferred: [BuddyTask]       // tasks "slept till tomorrow"
    var tombstones: [String: Double] = [:]  // { itemId: deletedAt } — deletes persist so a stale push can't resurrect them
    var erasedAt: Double? = nil             // top-level "erase all" timestamp (merge barrier)
}
