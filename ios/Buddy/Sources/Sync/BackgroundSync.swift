import Foundation
import BackgroundTasks

// MARK: - BackgroundSync — periodic sync while the app is closed.
//
// Field report (2026-07-14, first Buddy Cloud release): "it's almost like if the
// app isn't open it doesn't sync" — correct, iOS gives apps no free background
// time. BGAppRefreshTask is Apple's sanctioned slot: the system wakes the app
// briefly at times IT chooses (learned from usage; typically a handful of times
// a day — this narrows the staleness window, it does not eliminate it).
//
// Two execution shapes, both single-writer:
//   • App suspended but alive → the UI-owned SyncEngine still exists; run one
//     pass through IT so there is exactly one BuddyStore writing state.
//   • Cold background launch → no scene, no TodayView, no engine; we construct
//     the one and only BuddyStore, run one pass, adopt + persist, and exit.
//
// Registration MUST happen before the app finishes launching (BuddyApp.init);
// scheduling happens every time the app backgrounds (TodayView scenePhase) and
// after every fired task (re-arm).
enum BackgroundSync {
    static let taskId = "fyi.whale.buddy.refresh"   // must match BGTaskSchedulerPermittedIdentifiers

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            handle(refresh)
        }
    }

    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: taskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)   // a hint; iOS decides
        do { try BGTaskScheduler.shared.submit(req) }
        catch { BuddyDiag.log("bg-refresh-submit-failed", ["err": String("\(error)".prefix(80))]) }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()   // re-arm the next slot FIRST — even if this pass is cut short
        let work = Task { @MainActor in
            if let engine = SyncEngine.current {
                await engine.backgroundPass()
                BuddyDiag.log("bg-refresh", ["via": "engine"])
            } else {
                await coldPass()
                BuddyDiag.log("bg-refresh", ["via": "cold"])
            }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Cold background launch: no UI exists, so this BuddyStore is the process's
    /// only writer. One pull→merge→push pass, adopt + persist, done.
    @MainActor private static func coldPass() async {
        let cfg = SyncConfigStore.load().resolved
        guard cfg.isSyncable,
              let cas = SupabaseCASStore(url: cfg.backendUrl, anonKey: cfg.anonKey,
                                         syncKey: cfg.syncKey, device: "ios-bg") else { return }
        let store = BuddyStore()   // loads persisted state in init
        do {
            let res = try await BuddySync.syncOnce(store: cas,
                                                   key: SyncIdentity.ownerId(for: cfg.syncKey),
                                                   local: store.snapshot())
            if res.ok, let merged = res.merged, !res.noop { store.adopt(merged) }
        } catch {
            BuddyDiag.log("bg-refresh-error", ["err": String(error.localizedDescription.prefix(80))])
        }
    }
}
