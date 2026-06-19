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

    // Convenience: "done" row shows struck-through text in inkDim colour
    var isDone: Bool { state == .done }
    // Convenience: active = pressing on you (not done)
    var isActive: Bool { state != .done }
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

// MARK: - Full persisted state
// Mirrors the whole localStorage blob: { today, history, deferred, settings }
struct BuddyState: Codable {
    var today: TodayState
    var history: [Day]
    var deferred: [BuddyTask]   // tasks "slept till tomorrow"
}
