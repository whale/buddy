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
struct BuddyTask: Identifiable, Codable {
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
// Mirrors: state.history[] in the web app
// history items use a flat {id, text, done} shape (not full TaskState)
struct DayItem: Codable {
    var text: String
    var done: Bool
}

struct Day: Codable, Identifiable {
    // Use date as stable identity — one record per calendar day
    var id: String { date }
    var date: String    // "YYYY-MM-DD"
    var weekday: String // e.g. "Monday"
    var items: [DayItem]
}

// MARK: - Today's state
// Mirrors: state.today in the web app
struct TodayState: Codable {
    var date: String        // "YYYY-MM-DD"
    var items: [BuddyTask]
}

// MARK: - Deferred task model
// Mirrors the Mac's deferred[] shape: { id, text, wake }
struct DeferredTask: Codable, Identifiable {
    var id: String
    var text: String
    var wake: String  // "YYYY-MM-DD"
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
