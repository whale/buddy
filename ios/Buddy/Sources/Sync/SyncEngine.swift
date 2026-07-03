import Foundation
import Observation

// MARK: - SyncEngine (P2)
// Drives the sync loop for iOS. Single-flight + coalescing: only one pass runs at a time; any
// trigger that arrives mid-flight sets `pending` so exactly one more pass runs after — this is
// the "re-arm the dirty flag during an in-flight sync" guarantee (a change made while a push is
// on the wire is never lost). Triggers:
//   • launch / foreground (scenePhase == .active) → pull immediately
//   • local change (store.onLocalChange) → debounced push (coalesced)
//
// CRITICAL (M2): the DB row key is deriveOwnerId(syncKey) = sha256(syncKey), NOT the raw key.
// The Mac derives the same. Passing the raw key here would put the two devices in DIFFERENT
// buckets — each "syncs" perfectly to itself and never to the other.
//
// @MainActor: it mutates BuddyStore's @Observable state (adopt) and its own observable status,
// which the Settings UI reads. Network awaits suspend without blocking the UI.
@MainActor
@Observable
final class SyncEngine {
    // Observable status for the Settings UI.
    var lastSyncedAt: Date?
    var lastError: String?
    var isSyncing = false

    private weak var store: BuddyStore?
    private var config: SyncConfig
    private var pending = false
    private var debounce: Task<Void, Never>?

    static let debounceSeconds: UInt64 = 2_500_000_000   // 2.5s

    init(store: BuddyStore, config: SyncConfig = SyncConfigStore.load()) {
        self.store = store
        self.config = config
        store.onLocalChange = { [weak self] in self?.localChanged() }
    }

    // MARK: - Config
    func updateConfig(_ cfg: SyncConfig) {
        config = cfg
        if cfg.isSyncable { requestSync() }        // newly paired → pull immediately
    }
    var currentConfig: SyncConfig { config }

    // MARK: - Triggers
    /// Launch + every foreground: pull now (picks up the other device's edits).
    func syncOnForeground() { requestSync() }

    private func localChanged() {
        guard config.isSyncable else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceSeconds)
            guard let self, !Task.isCancelled else { return }
            self.requestSync()
        }
    }

    // MARK: - Single-flight driver
    private func requestSync() {
        guard config.isSyncable else { return }
        if isSyncing { pending = true; return }
        Task { await runLoop() }
    }

    private func runLoop() async {
        guard !isSyncing else { return }
        isSyncing = true
        repeat {
            pending = false
            await onePass()
        } while pending && config.isSyncable
        isSyncing = false
    }

    private func onePass() async {
        guard let store, config.isSyncable,
              let cas = SupabaseCASStore(url: config.backendUrl, anonKey: config.anonKey, device: "ios")
        else { return }
        let key = SyncIdentity.ownerId(for: config.syncKey)   // M2: hash, not the raw key
        let local = store.snapshot()
        do {
            let res = try await BuddySync.syncOnce(store: cas, key: key, local: local)
            if res.ok {
                if let merged = res.merged { store.adopt(merged) }
                lastSyncedAt = Date()
                lastError = nil
            } else {
                // Do NOT stamp a reassuring lastSyncedAt on failure — retries were exhausted.
                lastError = "Sync failed (server conflict — will retry)"
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
