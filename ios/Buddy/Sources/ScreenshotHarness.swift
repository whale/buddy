import SwiftUI

// MARK: - Screenshot harness (DEBUG only)
// Drives deterministic captures for the visual-parity workflow. Launch the app with
// a fixture argument and it seeds a fixed state + opens the right surface, so the
// simulator screenshot always shows the same thing:
//
//   xcrun simctl launch booted fyi.whale.buddy -uiFixture lvl2
//
// simctl turns `-uiFixture lvl2` into UserDefaults["uiFixture"] = "lvl2".
// Fixtures: lvl0 · lvl1 · lvl2 · empty · morning · history · settings · celebration
#if DEBUG
enum ScreenshotHarness {
    static var activeFixture: String? {
        UserDefaults.standard.string(forKey: "uiFixture")
    }

    /// Build a seeded store + the surface to show for the requested fixture.
    static func makeStore(for fixture: String) -> (store: BuddyStore, sheet: InitialSheetKind, forceMorning: Bool, celebrate: Bool) {
        let store = BuddyStore()
        // Deterministic capacity/theme fixtures; no morning control is added on iOS.
        let parts = fixture.split(separator: "-").map(String.init)
        if parts.count == 5, parts[0] == "settings", parts[1] == "limit", parts[3] == "level",
           let limit = Int(parts[2]), (3...6).contains(limit), let level = Int(parts[4]), (0...2).contains(level) {
            let count = limit - 2 + level
            store.seedForScreenshot(tasks: (0..<count).map { BuddyTask(id: "capacity\($0)", text: "Task \($0 + 1)", state: .neutral) })
            store.extras["taskLimit"] = TaskLimit(value: limit, v: 1, writer: "fixture").json
            store.syncNotice = nil
            return (store, .settings, false, false)
        }
        // future-<n>[-lvl1|-lvl2]: n parked rows of realistic length (fit / shrink / scroll shots).
        if parts.count >= 2, parts[0] == "future", let n = Int(parts[1]), n > 0 {
            let lvl = parts.count == 3 ? parts[2] : "lvl0"
            store.seedForScreenshot(tasks: lvl == "lvl2" ? MockData.alarmTasks : lvl == "lvl1" ? MockData.warningTasks : MockData.normalTasks)
            store.deferred = (0..<n).map { i in
                DeferredTask(id: "fn\(i + 1)", text: futureTitles[i % futureTitles.count] + (i >= futureTitles.count ? " \(i / futureTitles.count + 1)" : ""), wake: "")
            }
            return (store, .history, false, false)
        }
        switch fixture {
        case "done-many":
            // 6 done today + 20 archived days × 4 done → 86 completions: Done pages 30 at a time.
            let today = (0..<6).map { BuddyTask(id: "dm-t\($0)", text: "Today task \($0 + 1)", state: .done, doneAt: Date()) }
            store.seedForScreenshot(tasks: today + MockData.normalTasks.filter { !$0.isDone }, history: manyDoneHistory())
            return (store, .history, false, false)
        case "lvl0":
            store.seedForScreenshot(tasks: MockData.normalTasks)
            return (store, .none, false, false)
        case "lvl1":
            store.seedForScreenshot(tasks: MockData.warningTasks)
            return (store, .none, false, false)
        case "lvl2":
            store.seedForScreenshot(tasks: MockData.alarmTasks)
            return (store, .none, false, false)
        case "empty":
            store.seedForScreenshot(tasks: [])
            return (store, .none, false, false)
        case "long":
            store.seedForScreenshot(tasks: MockData.longTasks)
            return (store, .none, false, false)
        case "editing":
            store.seedForScreenshot(tasks: MockData.normalTasks)
            return (store, .none, false, false)
        case "done-tight":
            store.seedForScreenshot(tasks: (1...5).map { i in
                BuddyTask(id: "dt\(i)", text: "Finished item \(i)", state: .done, doneAt: Date())
            })
            return (store, .none, false, false)
        case "long-morning":
            store.seedForScreenshot(tasks: MockData.longTasks, morningDone: false)
            return (store, .none, true, false)
        case "morning":
            store.seedForScreenshot(tasks: MockData.normalTasks, morningDone: false)   // includes 2 done → Donezo rows on top
            return (store, .none, true, false)
        case "morning-restore":
            store.seedForScreenshot(tasks: [], history: recentHistory(), morningDone: false)   // empty → "Restore your last list"
            return (store, .none, true, false)
        case "history":
            store.seedForScreenshot(tasks: MockData.normalTasks, history: recentHistory())
            store.deferred = [DeferredTask(id: "f1", text: "Renew the domain", wake: "2026-07-05"),
                              DeferredTask(id: "f2", text: "Plan Q3 offsite", wake: "2026-07-10")]
            return (store, .history, false, false)
        case "history-full":
            store.seedForScreenshot(tasks: MockData.alarmTasks, history: recentHistory())
            store.deferred = [DeferredTask(id: "f1", text: "Renew the domain", wake: "2026-07-05"),
                              DeferredTask(id: "f2", text: "Plan Q3 offsite", wake: "2026-07-10")]
            return (store, .history, false, false)
        case "history-lvl1":
            store.seedForScreenshot(tasks: MockData.warningTasks, history: recentHistory())
            store.deferred = [DeferredTask(id: "f1", text: "Renew the domain", wake: "2026-07-05"),
                              DeferredTask(id: "f2", text: "Plan Q3 offsite", wake: "2026-07-10")]
            return (store, .history, false, false)
        case "future-sent-overflow":
            store.seedForScreenshot(tasks: MockData.normalTasks, history: recentHistory())
            store.deferred = [DeferredTask(id: "f1", text: "Renew the domain", wake: ""),
                              DeferredTask(id: "s1", text: "Email the accountant", wake: "", sent: true, sentTid: "x1", v: 2),
                              DeferredTask(id: "f2", text: "Plan Q3 offsite", wake: ""),
                              DeferredTask(id: "s2", text: "Book the vet", wake: "", sent: true, sentTid: "x2", v: 2),
                              DeferredTask(id: "f3", text: "Fix the bike", wake: "")]
            return (store, .history, false, false)
        case "future-sent":
            // Plain rows interleaved with sent ones in store order — sent must render on TOP, compact.
            store.seedForScreenshot(tasks: MockData.normalTasks, history: recentHistory())
            store.deferred = [DeferredTask(id: "f1", text: "Renew the domain", wake: ""),
                              DeferredTask(id: "s1", text: "Email the accountant", wake: "", sent: true, sentTid: "x1", v: 2),
                              DeferredTask(id: "f2", text: "Plan Q3 offsite", wake: ""),
                              DeferredTask(id: "s2", text: "Book the vet", wake: "", sent: true, sentTid: "x2", v: 2)]
            return (store, .history, false, false)
        case "future-long-lvl2":
            store.seedForScreenshot(tasks: MockData.alarmTasks)
            store.deferred = (1...12).map { i in
                DeferredTask(id: "fl\(i)", text: "Future item \(i)", wake: "2099-01-01")
            }
            return (store, .history, false, false)
        case "future-long":
            // 12 parked rows — the Future tab MUST scroll (field report 2026-07-10 R2-5).
            store.seedForScreenshot(tasks: MockData.normalTasks)
            store.deferred = (1...12).map { i in
                DeferredTask(id: "fl\(i)", text: "Future item \(i)", wake: "2099-01-01")
            }
            return (store, .history, false, false)
        case "settings":
            store.seedForScreenshot(tasks: MockData.normalTasks, history: recentHistory())
            return (store, .settings, false, false)
        case "boss":
            // 5 done + 2 active → the Boss Mode "Move to done" row appears under the done pile.
            let titles = ["Email Sam", "Draft the deck", "Call plumber", "Review PR", "Book flights"]
            var items = titles.enumerated().map { i, t in
                BuddyTask(id: "bd\(i)", text: t, state: .done, doneAt: Date())
            }
            items += [BuddyTask(id: "ba1", text: "Water plants", state: .neutral),
                      BuddyTask(id: "ba2", text: "Pay the invoice", state: .neutral)]
            store.seedForScreenshot(tasks: items)
            return (store, .none, false, false)
        case "boss-lvl2":
            // 6 active (lvl2 red) + 5 done → the Boss row must stay legible on the red background.
            var items = (0..<5).map { i in
                BuddyTask(id: "bd\(i)", text: ["Email Sam","Draft the deck","Call plumber","Review PR","Book flights"][i], state: .done, doneAt: Date())
            }
            items += (0..<6).map { i in BuddyTask(id: "ba\(i)", text: ["Ship it","Pay invoice","Water plants","Renew domain","Book flights","Plan offsite"][i], state: .neutral) }
            store.seedForScreenshot(tasks: items)
            return (store, .none, false, false)
        case "peer-unlinked":
            // Settings open, unpaired, with the "your Mac unlinked this device" note (mutual unlink).
            store.seedForScreenshot(tasks: MockData.normalTasks)
            return (store, .settings, false, false)
        case "sync-notice":
            // The overflow banner sits above the date card; alarmTasks = 6 active → lvl2 (red).
            store.seedForScreenshot(tasks: MockData.alarmTasks)
            store.syncNotice = SyncNotice(combined: 9, moved: 3, dismissed: false)
            return (store, .none, false, false)
        case "sync-notice-lvl0":
            store.seedForScreenshot(tasks: MockData.normalTasks)   // ≤4 active → lvl0 (white/black)
            store.syncNotice = SyncNotice(combined: 9, moved: 3, dismissed: false)
            return (store, .none, false, false)
        case "celebration-real":
            // Active tasks + a real completion fired from TodayView.task (see the DEBUG hook).
            store.seedForScreenshot(tasks: MockData.normalTasks)
            return (store, .none, false, false)
        case "celebration":
            store.seedForScreenshot(tasks: MockData.normalTasks)
            return (store, .none, false, true)
        case "celebration-quiet":
            // celebrate == 0 → the minimum celebration (one yellow hand pops up)
            store.seedForScreenshot(tasks: MockData.normalTasks)
            store.settings.celebrate = 0
            return (store, .none, false, true)
        default:
            store.seedForScreenshot(tasks: MockData.normalTasks)
            return (store, .none, false, false)
        }
    }

    static let futureTitles = ["Renew the domain", "Plan Q3 offsite", "Call the bank about the mortgage", "Fix the bike",
        "Book the vet", "Sort the garage shelves", "Email the accountant", "Order new running shoes",
        "Read the sync design doc", "Clean the gutters", "Back up the photo library", "Pick a birthday gift",
        "Update the portfolio site", "Return the library books", "Try the new ramen place", "Write to grandma"]

    private static func manyDoneHistory() -> [Day] {
        let cal = Calendar.current, wf = DateFormatter(); wf.dateFormat = "EEEE"
        return (1...20).map { back in
            let date = cal.date(byAdding: .day, value: -back, to: Date())!
            let ds = BuddyStore.localDate(date)
            return Day(date: ds, weekday: wf.string(from: date), items: (0..<4).map {
                DayItem(id: "dm-\(ds)-\($0)", text: "Day \(back) task \($0 + 1)", done: true) } +
                [DayItem(id: "dm-\(ds)-skip", text: "Skipped one", done: false)])
        }
    }

    // History records dated relative to *today* so the last-N-days window includes them.
    private static func recentHistory() -> [Day] {
        let cal = Calendar.current
        func day(_ back: Int, _ items: [(String, Bool)]) -> Day {
            let date = cal.date(byAdding: .day, value: -back, to: Date())!
            let ds = BuddyStore.localDate(date)
            let wf = DateFormatter(); wf.dateFormat = "EEEE"
            return Day(date: ds, weekday: wf.string(from: date),
                       items: items.enumerated().map { i, it in DayItem(id: "h-\(ds)-\(i)", text: it.0, done: it.1) })
        }
        return [
            day(1, [("Ship the done-word shuffle", true), ("Review the sync branch", true), ("Call the framer back", false)]),
            day(2, [("Fix the localStorage wipe", true), ("Write the data-safety plan", true)]),
            day(3, [("Morning run", true), ("Read the Sensei Fastfile", false)]),
            day(9, [("Draft the launch page", true), ("Email the printer", false)]),   // > a week back → "Load more"
        ]
    }
}
#endif
