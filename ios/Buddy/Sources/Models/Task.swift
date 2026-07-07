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

    // Convenience: "done" row shows struck-through text in inkDim colour
    var isDone: Bool { state == .done }
    // Convenience: active = pressing on you (not done)
    var isActive: Bool { state != .done }

    init(id: String, text: String, state: TaskState, doneAt: Date? = nil, v: Int = 1) {
        self.id = id; self.text = text; self.state = state; self.doneAt = doneAt; self.v = v
    }

    enum CodingKeys: String, CodingKey { case id, text, state, doneAt, v }

    // Tolerant decode: blobs written before `v` existed default to version 1.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = try c.decode(String.self, forKey: .id)
        text  = (try? c.decode(String.self, forKey: .text)) ?? ""
        state = (try? c.decode(TaskState.self, forKey: .state)) ?? .neutral
        doneAt = try? c.decodeIfPresent(Date.self, forKey: .doneAt)
        v     = (try? c.decodeIfPresent(Int.self, forKey: .v)) ?? 1
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

    init(date: String, items: [BuddyTask], morningDone: Bool = false) {
        self.date = date; self.items = items; self.morningDone = morningDone
    }
    enum CodingKeys: String, CodingKey { case date, items, morningDone }
    init(from d: Decoder) throws {       // tolerant: blobs saved before morningDone default to false
        let c = try d.container(keyedBy: CodingKeys.self)
        date  = (try? c.decode(String.self, forKey: .date)) ?? ""
        items = (try? c.decode([BuddyTask].self, forKey: .items)) ?? []
        morningDone = (try? c.decodeIfPresent(Bool.self, forKey: .morningDone)) ?? false
    }
}

// MARK: - Deferred task model
// Mirrors the Mac's deferred[] shape: { id, text, wake, sent?, sentTid? }
struct DeferredTask: Codable, Identifiable {
    var id: String
    var text: String
    var wake: String  // "YYYY-MM-DD"
    var sent: Bool? = nil       // "Sent to today!" confirmation (omitted when not sent)
    var sentTid: String? = nil  // id of the Today copy this was sent to, for undo
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
