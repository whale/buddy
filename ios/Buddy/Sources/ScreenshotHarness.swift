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
        switch fixture {
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
        case "sync-notice":
            // The overflow banner sits above the date card; alarmTasks = 6 active → lvl2 (red).
            store.seedForScreenshot(tasks: MockData.alarmTasks)
            store.syncNotice = SyncNotice(combined: 9, moved: 3, dismissed: false)
            return (store, .none, false, false)
        case "sync-notice-lvl0":
            store.seedForScreenshot(tasks: MockData.normalTasks)   // ≤4 active → lvl0 (white/black)
            store.syncNotice = SyncNotice(combined: 9, moved: 3, dismissed: false)
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
