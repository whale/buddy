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
    // "N tasks moved to Future on sync" banner — synced + dismissible (mirrors the Mac's
    // state.syncNotice). Set by a merge that relocated over-cap tasks; cleared on dismiss.
    var syncNotice: SyncNotice? = nil
    // Unknown top-level wire fields from a newer peer (the Mac's doneWordBag / pinned /
    // restartStash, future additions) — persisted + merged + pushed back untouched.
    var extras: [String: JSONValue] = [:]
    // "Last USER mutation" stamp (seconds) — merge() scalar conflicts key off this.
    // Bumped ONLY on a genuine local mutation (mirrors the Mac's save()); adopting a
    // pulled snapshot takes the merged max instead, so a device is never "newer" just
    // because it re-serialised (the 0.3.17 always-newer bug).
    private(set) var lastMutatedAt: Double = 0
    // True while a row edit is in flight in the UI. adopt() defers while set — a remote
    // apply mid-type would tear down the text field and could commit a half-typed task
    // (mirrors the Mac's applyWire editingId guard). The next sync pass re-merges.
    var isEditing = false

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
        // NO auto-wake: Future is a MANUAL holding pen on the Mac (no auto-return). The old
        // wakeDeferred() moved parked items into today on every launch (new id, no tombstone),
        // which the Mac never does — injecting a sync divergence that ping-ponged forever.
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

    /// Send a parked (Future) task to today — mirrors Mac's `addDeferredToToday`. The row
    /// STAYS in Future flipped to "Sent to today!" (no delete, no tombstone); `sentTid` links
    /// the Today copy for undo. Identical model on both platforms so sync converges.
    func wakeDeferredTask(id: String) {
        guard let idx = deferred.firstIndex(where: { $0.id == id }) else { return }
        guard !(deferred[idx].sent ?? false) else { return }
        guard activeCount < Self.hardCap else { return }
        let newTid = newId()
        today.items.append(BuddyTask(id: newTid, text: deferred[idx].text, state: .neutral))
        deferred[idx].sent = true
        deferred[idx].sentTid = newTid
        deferred[idx].v += 1               // send bumps the row's merge version (beats a stale peer copy)
        scheduleSave()
    }

    /// Undo a "Sent to today!" row — remove the Today copy and return a plain, sendable row.
    /// Mirrors Mac's `unsendDeferred`.
    func unsendDeferred(id: String) {
        guard let idx = deferred.firstIndex(where: { $0.id == id }) else { return }
        guard deferred[idx].sent == true else { return }
        if let tid = deferred[idx].sentTid {
            tombstone(tid)
            today.items.removeAll { $0.id == tid }
        }
        deferred[idx].sent = nil           // cleared, not false — the wire omits an unset sent
        deferred[idx].sentTid = nil
        deferred[idx].v += 1               // unsend also bumps — undo must beat the peer's sent copy
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
    /// Tombstone the id so a stale push from the other device can't resurrect it.
    func deleteDeferred(id: String) {
        tombstone(id)
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

    /// Build the mergeable snapshot the sync loop pushes. savedAt is the LAST USER
    /// MUTATION stamp — NEVER Date() — so an idle snapshot doesn't claim "newer" and
    /// steamroll the other device's scalar fields (mirrors the Mac's serialize()).
    func snapshot() -> SyncSnapshot {
        SyncSnapshot(today: today, history: history, deferred: deferred, settings: settings,
                     tombstones: tombstones, erasedAt: erasedAt, savedAt: lastMutatedAt,
                     syncNotice: SyncNotice.sanitized(syncNotice), extras: extras)
    }

    /// Dismiss the "moved to Future" banner. A user mutation → bumps lastMutatedAt so the
    /// dismissed flag wins the merge and clears on the other device too (mirrors the Mac).
    func dismissSyncNotice() {
        guard var n = SyncNotice.sanitized(syncNotice) else { return }
        n.dismissed = true
        syncNotice = n
        scheduleSave(immediate: true)
    }

    /// Replace local state from a merged snapshot (the result of a pull+merge). Persists directly
    /// and NEVER fires onLocalChange — adopting remote truth must not schedule another push. Must
    /// be called on the main actor (mutates @Observable state the UI reads). Fires no celebration.
    /// Deferred while a row edit is in flight (isEditing) — the next pass re-merges.
    func adopt(_ merged: SyncSnapshot) {
        guard !isEditing else { BuddyDiag.log("adopt-deferred-editing"); return }   // never clobber an in-progress edit (Mac applyWire parity)
        applyingRemote = true
        defer { applyingRemote = false }
        if let t = merged.today { today = t }
        history    = merged.history
        deferred   = merged.deferred
        if let s = merged.settings { settings = s }
        tombstones = merged.tombstones
        erasedAt   = merged.erasedAt
        syncNotice = SyncNotice.sanitized(merged.syncNotice)
        extras     = merged.extras
        lastMutatedAt = merged.savedAt       // adopt the merged max — adopting must NOT claim newer
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
    // Mirrors the Mac's `maybeRollover()` + `rolloverAndCarry()` (dist/index.html).
    @discardableResult
    func performRolloverIfNeeded() -> Bool {
        guard !isEditing else { return false }             // never roll over mid-edit (Mac parity)
        let cur = Self.localDate()
        let stored = today.date
        guard stored != cur else { return false }          // same day → restore verbatim
        guard !stored.isEmpty else { today.date = cur; return false }

        let hadLive = !today.items.isEmpty

        if hadLive && !history.contains(where: { $0.date == stored }) {
            // Archive today's list — stable per-day ids (h-<date>-<i>) match the Mac so
            // cross-device history merges by id.
            if let record = BuddyMerge.todayToHistoryRecord(today) {
                history.insert(record, at: 0)
            }
            today = TodayState(date: cur, items: [])
        } else if hadLive {
            // Day already archived (the other device rolled first, or a clock rewind) —
            // MERGE the live items into the existing record instead of dropping them
            // (done-wins, same positional ids as the peer's archive so the union dedupes).
            if let idx = history.firstIndex(where: { $0.date == stored }),
               let live = BuddyMerge.todayToHistoryRecord(today) {
                let m = BuddyMerge.mergeHistRecord(history[idx], live)
                history[idx].items = m.items
                history[idx].weekday = m.weekday
            }
            today = TodayState(date: cur, items: [])
        } else {
            // Empty/skipped day → advance the date AND reset morningDone (archive nothing).
            today = TodayState(date: cur, items: [])
        }

        // A new day: "Sent to today!" rows have served their purpose — clear them
        // (matches rolloverAndCarry's `deferred.filter(d=>!d.sent)` + sentTid wipe).
        deferred = deferred.filter { !($0.sent ?? false) }
        for i in deferred.indices { deferred[i].sentTid = nil }

        // Carry the archived day's UNFINISHED tasks forward (first hardCap of them, deduped
        // by text, fresh ids) — but only when there WERE live items pre-rollover. Reads the
        // record for `stored` (not "did history grow") so the already-archived branch —
        // where the other device rolled the day first — carries forward too.
        if hadLive, let rec = history.first(where: { $0.date == stored }) {
            for it in rec.items.filter({ !$0.done }).prefix(Self.hardCap) {
                if activeCount < Self.hardCap && !today.items.contains(where: { $0.text == it.text }) {
                    today.items.append(BuddyTask(id: newId(), text: it.text, state: .neutral))
                }
            }
        }

        scheduleSave(immediate: true)
        return true                                        // → caller shows morning
    }

    // (Removed auto-wakeDeferred: Future is a manual holding pen on both platforms now.)

    // MARK: - Persistence

    private static var storeDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let buddyDir = dir.appendingPathComponent("Buddy", isDirectory: true)
        try? FileManager.default.createDirectory(at: buddyDir, withIntermediateDirectories: true)
        return buddyDir
    }
    static var storeURL: URL   { storeDir.appendingPathComponent("buddy.v1.json") }
    static var backupURL: URL  { storeDir.appendingPathComponent("buddy.v1.bak.json") }
    /// An unreadable primary is MOVED here (kept for forensics) before anything can overwrite it.
    static var corruptURL: URL { storeDir.appendingPathComponent("buddy.v1.corrupt.json") }

    private func scheduleSave(immediate: Bool = false) {
        // A local mutation → stamp "last user mutation" (merge scalars key off it) and
        // signal the sync engine to schedule a debounced push. Both suppressed while
        // adopting a remote snapshot (that write is the RESULT of a pull, not a new edit).
        if !applyingRemote {
            lastMutatedAt = Date().timeIntervalSince1970
            onLocalChange?()
        }
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
            savedAt: lastMutatedAt,   // last USER mutation — a re-save must not claim "newer"
            today: today,
            history: history,
            deferred: deferred,
            settings: settings,
            tombstones: tombstones,
            erasedAt: erasedAt,
            syncNotice: SyncNotice.sanitized(syncNotice),
            extras: extras
        )
        do {
            let data = try JSONEncoder().encode(blob)
            try data.write(to: Self.storeURL, options: .atomic)
        } catch {
            print("[BuddyStore] save failed: \(error)")
        }
    }

    /// Corruption guard: an unreadable primary is SET ASIDE (buddy.v1.corrupt.json) before
    /// anything can overwrite it, then the backup is tried, then we fall back to a fresh
    /// state. Every successful primary load refreshes the backup copy.
    private func loadFromDisk() {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: Self.storeURL) else { return }   // first run — nothing on disk
        if applyPersistedData(data) {
            // Good primary → refresh the backup so a future corruption is recoverable.
            try? fm.removeItem(at: Self.backupURL)
            try? fm.copyItem(at: Self.storeURL, to: Self.backupURL)
            return
        }
        // Primary is unreadable. Move it aside FIRST — init()'s scheduleSave would
        // otherwise overwrite the only copy of whatever it still contains.
        print("[BuddyStore] primary store unreadable — setting it aside at \(Self.corruptURL.lastPathComponent)")
        try? fm.removeItem(at: Self.corruptURL)
        try? fm.moveItem(at: Self.storeURL, to: Self.corruptURL)
        if let bak = try? Data(contentsOf: Self.backupURL), applyPersistedData(bak) {
            print("[BuddyStore] recovered from backup \(Self.backupURL.lastPathComponent)")
            return
        }
        print("[BuddyStore] no recoverable backup — starting fresh (original kept for forensics)")
    }

    /// Decode + apply one persisted blob. Returns false (leaving state untouched) on failure.
    private func applyPersistedData(_ data: Data) -> Bool {
        guard let blob = try? JSONDecoder().decode(PersistedBlob.self, from: data) else { return false }
        today    = blob.today ?? TodayState(date: Self.localDate(), items: [])
        history  = (blob.history ?? []).map { var d = $0; d.backfillItemIds(); return d }   // legacy records get stable ids
        deferred = blob.deferred ?? []
        settings = blob.settings ?? .default
        tombstones = blob.tombstones ?? [:]
        erasedAt   = blob.erasedAt
        syncNotice = SyncNotice.sanitized(blob.syncNotice)
        extras     = blob.extras ?? [:]
        lastMutatedAt = blob.savedAt          // restore the "last user mutation" stamp
        return true
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
}

// MARK: - Serialised blob
// Mirrors the Mac's localStorage blob: { version, savedAt, today, history, deferred, settings }
// All fields optional so partial/corrupted data doesn't crash load.
private struct PersistedBlob: Codable {
    var version: Int
    var savedAt: Double          // last USER mutation (seconds) — restored into lastMutatedAt
    var today: TodayState?
    var history: [Day]?
    var deferred: [DeferredTask]?
    var settings: BuddySettings?
    var tombstones: [String: Double]?
    var erasedAt: Double?
    var syncNotice: SyncNotice?
    // Unknown top-level wire fields (version-skew pass-through). Local-only file, so a
    // plain nested key is fine here — the wire spreads them at the top level instead.
    var extras: [String: JSONValue]?
}
