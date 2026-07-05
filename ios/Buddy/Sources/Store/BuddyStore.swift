import Foundation
import Observation

// MARK: - BuddyStore
// The single source of truth for the iOS app, mirroring the Mac app's state model.
// Persists to a JSON file in Application Support so the future sync layer can reuse it.
//
// Serialised shape mirrors the Mac's localStorage blob:
//   { version, savedAt, today, history, deferred, settings }
// — so a future sync layer can share the same blob format.
@Observable
final class BuddyStore {

    // MARK: - Caps (mirror Mac's SOFT_CAP / HARD_CAP)
    static let softCap = 5
    static let hardCap = 6

    // MARK: - State (mirrors Mac's `state` object)
    var today: TodayState = TodayState(date: localDate(), items: [])
    var history: [Day] = []
    var deferred: [DeferredTask] = []
    var settings: BuddySettings = .default
    // --- sync merge foundation (step 2, no network yet) ---
    var tombstones: [String: Double] = [:]  // { itemId: deletedAt } — deletes persist across a merge
    var erasedAt: Double? = nil             // "erase all" barrier so a real wipe wins over stale pushes

    // MARK: - Derived helpers
    var activeTasks: [BuddyTask] { today.items.filter { $0.isActive } }
    var doneTasks: [BuddyTask]   { today.items.filter { $0.isDone } }
    var activeCount: Int         { activeTasks.count }
    var atHardCap: Bool          { activeCount >= Self.hardCap }

    // MARK: - Save debounce
    private var saveWorkItem: DispatchWorkItem?

    // MARK: - Sync hooks (P1.5/P2)
    // The sync engine sets onLocalChange to schedule a debounced push. While `applyingRemote`
    // is true (inside adopt), local mutations are the RESULT of a pull — they must NOT re-trigger
    // a push (that ping-pongs versions). adopt() persists directly and never fires onLocalChange.
    var onLocalChange: (() -> Void)?
    private var applyingRemote = false

    // MARK: - Init
    init() {
        loadFromDisk()
        performRolloverIfNeeded()
        wakeDeferred()
        scheduleSave()
    }

    // MARK: - Merge helpers (sync step 2)
    // A delete records a tombstone instead of dropping silently, so a later stale push
    // from another device can't resurrect the deleted task. Mirrors Mac's tombstone().
    private func tombstone(_ id: String) {
        tombstones[id] = Date().timeIntervalSince1970
    }

    // MARK: - Task mutations

    /// Tap cycle: neutral → focused → done → neutral (restore).
    /// Mirrors Mac's `cycle(it)` function.
    func cycle(_ task: BuddyTask) -> Bool {
        guard let idx = today.items.firstIndex(where: { $0.id == task.id }) else { return false }
        var t = today.items[idx]
        let wasDone = t.state == .done
        switch t.state {
        case .neutral:
            // Clear any existing focused task first, then focus this one.
            for i in today.items.indices where today.items[i].state == .focused {
                today.items[i].state = .neutral
                today.items[i].v += 1
            }
            t.state = .focused
        case .focused:
            t.state = .done
            t.doneAt = Date()
        case .done:
            guard activeCount < Self.hardCap else { return false }
            t.state = .neutral
            t.doneAt = nil
        }
        t.v += 1                       // any state change bumps the merge version
        today.items[idx] = t
        scheduleSave()
        // Return true if we just completed (transitioned into done) — caller fires celebration
        return !wasDone && today.items[idx].state == .done
    }

    /// Direct complete (the check-off circle): marks done from any state. Returns true on a
    /// transition INTO done so the caller fires the celebration. Mirrors a row landing on done.
    @discardableResult
    func complete(_ task: BuddyTask) -> Bool {
        guard let idx = today.items.firstIndex(where: { $0.id == task.id }) else { return false }
        let wasDone = today.items[idx].state == .done
        today.items[idx].state = .done
        today.items[idx].doneAt = Date()
        today.items[idx].v += 1
        scheduleSave()
        return !wasDone
    }

    /// Add a new blank task. Returns the new task's id so the caller can auto-focus the text field.
    func addTask() -> String? {
        guard activeCount < Self.hardCap else { return nil }
        let newTask = BuddyTask(id: newId(), text: "", state: .neutral)
        today.items.append(newTask)
        scheduleSave()
        return newTask.id
    }

    /// Commit edited text for a task. If text is empty, remove the task.
    func commitEdit(id: String, text: String) {
        guard let idx = today.items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            tombstone(today.items[idx].id)
            today.items.remove(at: idx)
        } else if today.items[idx].text != trimmed {
            today.items[idx].text = trimmed
            today.items[idx].v += 1            // a committed text change bumps the merge version
        }
        scheduleSave()
    }

    /// Delete a task by id.
    func deleteTask(id: String) {
        tombstone(id)                          // record the delete so a stale push can't resurrect it
        today.items.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Restore a done task back to active (capped at hardCap).
    /// Mirrors Mac's `restoreItem(id)`.
    func restoreTask(id: String) {
        guard let idx = today.items.firstIndex(where: { $0.id == id }) else { return }
        guard activeCount < Self.hardCap else { return }
        today.items[idx].state = .neutral
        today.items[idx].doneAt = nil
        today.items[idx].v += 1
        scheduleSave()
    }

    /// Bring a PAST (skipped) task back into today by text — fresh id, capped, no dupes.
    /// Mirrors Mac's `restoreHistoryTask(text)`.
    func restoreHistoryTask(text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, activeCount < Self.hardCap else { return }
        guard !today.items.contains(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == t }) else { return }
        today.items.append(BuddyTask(id: newId(), text: t, state: .neutral))
        scheduleSave()
    }

    /// Pull a parked (Future) task into today's list, then drop it from deferred.
    /// Mirrors Mac's Future-tab restore.
    func wakeDeferredTask(id: String) {
        guard let idx = deferred.firstIndex(where: { $0.id == id }) else { return }
        guard activeCount < Self.hardCap else { return }
        today.items.append(BuddyTask(id: newId(), text: deferred[idx].text, state: .neutral))
        deferred.remove(at: idx)
        scheduleSave()
    }

    /// Most recent archived day's unfinished tasks — for the morning "Restore your last list".
    /// Mirrors the Mac's mostRecentRestorableRecord + restorableTexts.
    func lastListForRestore() -> [String] {
        for d in history.sorted(by: { $0.date > $1.date }) {
            let texts = d.items.filter { !$0.done }.map { $0.text }.filter { !$0.isEmpty }
            if !texts.isEmpty { return Array(texts.prefix(Self.hardCap)) }
        }
        return []
    }

    /// Pull that list into today (capped, no dupes). Mirrors the Mac's restoreLastList().
    func restoreLastList() {
        for t in lastListForRestore() where activeCount < Self.hardCap {
            if !today.items.contains(where: { $0.text == t }) {
                today.items.append(BuddyTask(id: newId(), text: t, state: .neutral))
            }
        }
        scheduleSave()
    }

    /// True if any archived day is older than `days` back — drives History "Load more".
    func hasHistoryBefore(days: Int) -> Bool {
        guard let boundary = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return false }
        let ds = Self.localDate(boundary)
        return history.contains { $0.date < ds }
    }

    /// Remove a parked (Future) task for good. Mirrors the Mac Future-tab × button.
    func deleteDeferred(id: String) {
        deferred.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Every completed task text (today + history), newest first — for the Settings export.
    var doneExport: [String] {
        var out = store_todayDone()
        for d in history { out += d.items.filter { $0.done }.map { $0.text } }
        return out
    }
    private func store_todayDone() -> [String] { doneTasks.map { $0.text } }

    /// Push a task to tomorrow's deferred list. Mirrors Mac's `sleepItem(id)`.
    func deferToTomorrow(id: String) {
        guard let idx = today.items.firstIndex(where: { $0.id == id }) else { return }
        let task = today.items[idx]
        let wake = tomorrowDateString()
        deferred.append(DeferredTask(id: newId(), text: task.text, wake: wake))
        tombstone(id)                          // it leaves today under a new deferred id → tombstone the old one
        today.items.remove(at: idx)
        scheduleSave()
    }

    /// Erase everything and stamp erasedAt so the wipe wins over any later stale push.
    /// Mirrors Mac's `eraseAll()`. No Settings button yet — foundation for the merge.
    func eraseAll() {
        today = TodayState(date: Self.localDate(), items: [])
        history = []
        deferred = []
        tombstones = [:]
        erasedAt = Date().timeIntervalSince1970
        scheduleSave(immediate: true)
    }

    #if DEBUG
    // Screenshot/preview seed: replace state directly so a fixture renders exactly as
    // given. Rollover already ran in init() but is a no-op for today's date, and this
    // overwrites its result anyway. Not persisted — purely for deterministic captures.
    func seedForScreenshot(tasks: [BuddyTask], history: [Day] = [], morningDone: Bool = true, settings: BuddySettings = .default) {
        saveWorkItem?.cancel()
        today = TodayState(date: Self.localDate(), items: tasks, morningDone: morningDone)
        self.history = history
        deferred = []
        tombstones = [:]
        erasedAt = nil
        self.settings = settings
    }

    // Dev-only: wipe to a clean first-run state so the morning planner shows again.
    func resetForDev() {
        today = TodayState(date: Self.localDate(), items: [], morningDone: false)
        history = []
        deferred = []
        tombstones = [:]
        erasedAt = nil
        scheduleSave(immediate: true)
    }
    #endif

    // MARK: - Sync bridge (P1.5)

    /// Build the mergeable snapshot the sync loop pushes. savedAt is stamped NOW (mirrors the
    /// Mac's serialize()), so a genuine local change wins scalar (settings / today.date) conflicts.
    func snapshot() -> SyncSnapshot {
        SyncSnapshot(today: today, history: history, deferred: deferred, settings: settings,
                     tombstones: tombstones, erasedAt: erasedAt, savedAt: Date().timeIntervalSince1970)
    }

    /// Replace local state from a merged snapshot (the result of a pull+merge). Persists directly
    /// and NEVER fires onLocalChange — adopting remote truth must not schedule another push. Must
    /// be called on the main actor (mutates @Observable state the UI reads). Fires no celebration.
    func adopt(_ merged: SyncSnapshot) {
        applyingRemote = true
        defer { applyingRemote = false }
        if let t = merged.today { today = t }
        history    = merged.history
        deferred   = merged.deferred
        if let s = merged.settings { settings = s }
        tombstones = merged.tombstones
        erasedAt   = merged.erasedAt
        saveToDisk()                         // persist without going through scheduleSave/dirty
    }

    // MARK: - Morning planner
    // Mirrors the Mac: on a fresh/rolled day the morning planner shows until the user
    // presses Buddy! (or Skip) — both just mark the day planned. Yesterday's unfinished
    // tasks are already carried into `today.items` by the rollover, so the planner shows
    // them automatically before the day "starts".
    var needsMorning: Bool { !today.morningDone }

    /// Buddy! — finish planning, keep the chosen tasks.
    func completeMorning() {
        today.morningDone = true
        scheduleSave(immediate: true)
    }

    /// Skip — same effect (the day is marked planned); mirrors the Mac's skip().
    func skipMorning() {
        today.morningDone = true
        scheduleSave(immediate: true)
    }

    // MARK: - Rollover
    // Mirrors Mac's `maybeRollover()` + the carry-over in `bootFinish()`.
    @discardableResult
    func performRolloverIfNeeded() -> Bool {
        let cur = Self.localDate()
        let stored = today.date
        guard stored != cur else { return false }

        // Archive today's tasks into history — but only once per day. If this date is
        // already in history (a second rollover this run, or a record merged in from
        // another device), don't duplicate it. Closes the double-midnight loss path.
        if !today.items.isEmpty && !history.contains(where: { $0.date == stored }) {
            let wd = weekdayName(for: stored)
            let record = Day(
                date: stored,
                weekday: wd,
                // Stable per-day ids (h-<date>-<i>) match the Mac so cross-device history merges by id.
                items: today.items.enumerated().map { i, t in
                    DayItem(id: "h-\(stored)-\(i)", text: t.text, done: t.state == .done)
                }
            )
            history.insert(record, at: 0)

            // Carry ALL unfinished tasks forward (up to the hard cap of 6, the full list).
            let unfinished = record.items.filter { !$0.done }.prefix(Self.hardCap)
            var carryItems: [BuddyTask] = []
            for item in unfinished where carryItems.count < Self.hardCap {
                carryItems.append(BuddyTask(id: newId(), text: item.text, state: .neutral))
            }
            today = TodayState(date: cur, items: carryItems)
            scheduleSave(immediate: true)
            return true
        }

        // Day already archived (idempotent) or nothing to archive — advance to a fresh day.
        // NOTE (sync): this resets morningDone to false, which is correct for a genuinely new
        // day. A sync-merged archive for `stored` could also land here while today still holds
        // the old date — revisit when wiring live sync so a merge can't re-trigger the morning.
        today = TodayState(date: cur, items: [])
        scheduleSave(immediate: true)
        return true
    }

    // MARK: - Wake deferred tasks
    // Mirrors Mac's `wakeDeferred()`.
    private func wakeDeferred() {
        let today = Self.localDate()
        var keep: [DeferredTask] = []
        for d in deferred {
            if d.wake <= today && activeCount < Self.hardCap {
                let task = BuddyTask(id: newId(), text: d.text, state: .neutral)
                self.today.items.append(task)
            } else {
                keep.append(d)
            }
        }
        deferred = keep
    }

    // MARK: - Persistence

    private static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let buddyDir = dir.appendingPathComponent("Buddy", isDirectory: true)
        try? FileManager.default.createDirectory(at: buddyDir, withIntermediateDirectories: true)
        return buddyDir.appendingPathComponent("buddy.v1.json")
    }

    private func scheduleSave(immediate: Bool = false) {
        // A local mutation → signal the sync engine to schedule a debounced push. Suppressed
        // while adopting a remote snapshot (that write is the RESULT of a pull, not a new edit).
        if !applyingRemote { onLocalChange?() }
        saveWorkItem?.cancel()
        if immediate {
            saveToDisk()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.saveToDisk() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func saveToDisk() {
        let blob = PersistedBlob(
            version: 1,
            savedAt: Date().timeIntervalSince1970,
            today: today,
            history: history,
            deferred: deferred,
            settings: settings,
            tombstones: tombstones,
            erasedAt: erasedAt
        )
        do {
            let data = try JSONEncoder().encode(blob)
            try data.write(to: Self.storeURL, options: .atomic)
        } catch {
            print("[BuddyStore] save failed: \(error)")
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: Self.storeURL) else { return }
        do {
            let blob = try JSONDecoder().decode(PersistedBlob.self, from: data)
            today    = blob.today ?? TodayState(date: Self.localDate(), items: [])
            history  = (blob.history ?? []).map { var d = $0; d.backfillItemIds(); return d }   // legacy records get stable ids
            deferred = blob.deferred ?? []
            settings = blob.settings ?? .default
            tombstones = blob.tombstones ?? [:]
            erasedAt   = blob.erasedAt
        } catch {
            print("[BuddyStore] load failed: \(error)")
        }
    }

    // MARK: - ID generation (mirrors Mac's nid())
    // Globally-unique IDs (UUID), NOT a per-device counter — two devices both
    // minting n1,n2,… would collide on sync and corrupt a cross-device merge.
    private func newId() -> String { UUID().uuidString }

    // MARK: - Date helpers (mirrors Mac's localDate())
    static func localDate(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale.current
        return f.string(from: date)
    }

    private func tomorrowDateString() -> String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        return Self.localDate(tomorrow)
    }

    private func weekdayName(for dateString: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: dateString) else { return "" }
        let wf = DateFormatter()
        wf.dateFormat = "EEEE"
        return wf.string(from: date)
    }
}

// MARK: - Serialised blob
// Mirrors the Mac's localStorage blob: { version, savedAt, today, history, deferred, settings }
// All fields optional so partial/corrupted data doesn't crash load.
private struct PersistedBlob: Codable {
    var version: Int
    var savedAt: Double
    var today: TodayState?
    var history: [Day]?
    var deferred: [DeferredTask]?
    var settings: BuddySettings?
    var tombstones: [String: Double]?
    var erasedAt: Double?
}
