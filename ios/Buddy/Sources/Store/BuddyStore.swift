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
                items: today.items.map { DayItem(text: $0.text, done: $0.state == .done) }
            )
            history.insert(record, at: 0)

            // Hybrid carry-over: pre-fill today with yesterday's unfinished tasks (up to softCap).
            // Mirrors Mac's bootFinish carry-over block.
            let unfinished = record.items.filter { !$0.done }.prefix(Self.softCap)
            var carryItems: [BuddyTask] = []
            for item in unfinished where carryItems.count < Self.hardCap {
                carryItems.append(BuddyTask(id: newId(), text: item.text, state: .neutral))
            }
            today = TodayState(date: cur, items: carryItems)
            scheduleSave(immediate: true)
            return true
        }

        // Day already archived (idempotent) or nothing to archive — advance to a fresh day.
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
            history  = blob.history ?? []
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
