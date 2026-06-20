import Foundation

// MARK: - Mock data for previews and scaffold testing
// Covers all escalation levels:
//   lvl0 — ≤4 active tasks (normal: black text, white background)
//   lvl1 — exactly 5 active tasks (warning: red text, white background)
//   lvl2 — ≥6 active tasks (alarm: white text, red background)

enum MockData {

    // MARK: Normal state (4 active + 2 done = lvl0)
    static let normalTasks: [BuddyTask] = [
        BuddyTask(id: "m1", text: "Write the iOS scaffold", state: .focused),
        BuddyTask(id: "m2", text: "Review sync plan", state: .neutral),
        BuddyTask(id: "m3", text: "Ship the Mac durability fix", state: .neutral),
        BuddyTask(id: "m4", text: "Read the IOS-COMPANION-PLAN.md", state: .neutral),
        BuddyTask(id: "m5", text: "Answer emails", state: .done, doneAt: Date()),
        BuddyTask(id: "m6", text: "Morning walk", state: .done, doneAt: Date()),
    ]

    // MARK: Warning state (5 active = lvl1 — all text turns red)
    static let warningTasks: [BuddyTask] = [
        BuddyTask(id: "w1", text: "Write the iOS scaffold", state: .focused),
        BuddyTask(id: "w2", text: "Review sync plan", state: .neutral),
        BuddyTask(id: "w3", text: "Ship the Mac durability fix", state: .neutral),
        BuddyTask(id: "w4", text: "Read the plan doc", state: .neutral),
        BuddyTask(id: "w5", text: "Email the client", state: .neutral),
        BuddyTask(id: "w6", text: "Morning walk", state: .done, doneAt: Date()),
    ]

    // MARK: Alarm state (6 active = lvl2 — red background, light text)
    static let alarmTasks: [BuddyTask] = [
        BuddyTask(id: "a1", text: "Write the iOS scaffold", state: .focused),
        BuddyTask(id: "a2", text: "Review sync plan", state: .neutral),
        BuddyTask(id: "a3", text: "Ship the Mac durability fix", state: .neutral),
        BuddyTask(id: "a4", text: "Read the plan doc", state: .neutral),
        BuddyTask(id: "a5", text: "Email the client", state: .neutral),
        BuddyTask(id: "a6", text: "Design the settings screen", state: .neutral),
        BuddyTask(id: "a7", text: "Morning walk", state: .done, doneAt: Date()),
    ]

    // MARK: History days
    static let historyDays: [Day] = [
        Day(
            date: "2026-06-17",
            weekday: "Tuesday",
            items: [
                DayItem(id: "h-2026-06-17-0", text: "Ship Buddy v0.2.15", done: true),
                DayItem(id: "h-2026-06-17-1", text: "Write IOS plan doc", done: true),
                DayItem(id: "h-2026-06-17-2", text: "Call with team", done: false),
            ]
        ),
        Day(
            date: "2026-06-16",
            weekday: "Monday",
            items: [
                DayItem(id: "h-2026-06-16-0", text: "Fix localStorage wipe bug", done: true),
                DayItem(id: "h-2026-06-16-1", text: "Review DATA-SAFETY-PLAN.md", done: true),
                DayItem(id: "h-2026-06-16-2", text: "Design weekly review", done: true),
            ]
        ),
        Day(
            date: "2026-06-15",
            weekday: "Sunday",
            items: [
                DayItem(id: "h-2026-06-15-0", text: "Morning run", done: true),
                DayItem(id: "h-2026-06-15-1", text: "Read Sensei Fastfile", done: false),
            ]
        ),
    ]

    // MARK: Full state (normal level)
    static let normalState = BuddyState(
        today: TodayState(date: "2026-06-18", items: normalTasks),
        history: historyDays,
        deferred: []
    )
}
