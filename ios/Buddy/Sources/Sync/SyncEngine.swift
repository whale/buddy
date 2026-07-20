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
    var peerUnlinked = false          // the OTHER device dissolved the link — show the note until re-pair
    private var unlinking = false     // guards our own marker from being read back as a peer-unlink

    /// The UI-owned engine, reachable from a fired BGAppRefreshTask so a background
    /// pass reuses the live BuddyStore (one writer) instead of constructing a second.
    static weak var current: SyncEngine?

    private weak var store: BuddyStore?
    private var config: SyncConfig
    private var pending = false
    private var debounce: Task<Void, Never>?
    private var pollTimer: Timer?

    static let debounceSeconds: UInt64 = 800_000_000   // 0.8s — snappy local→remote push
    static let pollSeconds: TimeInterval = 1.5         // remote→local: poll while foreground

    init(store: BuddyStore, config: SyncConfig = SyncConfigStore.load()) {
        self.store = store
        self.config = config
        store.onLocalChange = { [weak self] in self?.localChanged() }
        Self.current = self
    }

    /// One pass for a BGAppRefreshTask — no polling, no debounce, just catch up.
    func backgroundPass() async { await onePass() }

    // MARK: - Config
    func updateConfig(_ cfg: SyncConfig) {
        config = cfg
        if cfg.isSyncable { peerUnlinked = false; requestSync(); startPolling() }   // newly (re)paired → clear the note, go live
        else { stopPolling() }
    }
    var currentConfig: SyncConfig { config }

    // MARK: - Mutual unlink (whale 2026-07-19) — unlinking one device breaks the link for BOTH.
    /// Stamp the shared bucket so the peer self-unlinks on its next pass, THEN clear our own link.
    /// Best-effort marker push (offline → local-only unlink). Returns whether the peer was signalled.
    @discardableResult
    func unlinkMutual() async -> Bool {
        unlinking = true
        defer { unlinking = false }
        let signalled = await pushUnlinkMarker()
        clearLink()
        peerUnlinked = false
        return signalled
    }

    /// One CAS push of the current remote blob + an `unlinkedAt` marker (read by the peer BEFORE
    /// any merge, in syncOnce). Best-effort: offline / conflict → the peer just stays linked.
    private func pushUnlinkMarker() async -> Bool {
        let live = config.resolved
        guard live.enabled, Self.validKey(live.syncKey),
              let cas = SupabaseCASStore(url: live.backendUrl, anonKey: live.anonKey,
                                         syncKey: live.syncKey, device: "ios")
        else { return false }
        let key = SyncIdentity.ownerId(for: config.syncKey)
        // RETRY on CAS conflict: a concurrent in-flight pass (1.5s poll / debounce) can bump the
        // version between our pull and push. Without retry the marker fails to land and the peer
        // never unlinks. Re-pull, re-stamp, re-push — the marker MUST land.
        do {
            for _ in 0..<BuddySync.maxRetry {
                let remote = try await cas.pull(key)
                if remote.unreadable { return false }           // a newer-format peer row — don't clobber
                if let ua = remote.blob?.unlinkedAt, ua > 0 { return true }   // already stamped → done
                guard var blob = remote.blob ?? store?.snapshot() else { return false }
                blob.unlinkedAt = Date().timeIntervalSince1970
                let res = try await cas.push(key, blob: blob, expected: remote.version)
                if res.ok { BuddyDiag.log("unlink-marker", ["ok": true]); return true }
                if res.unreadable { return false }
            }
            BuddyDiag.log("unlink-marker", ["ok": false])
            return false
        } catch { BuddyDiag.log("unlink-marker-failed"); return false }
    }

    /// Drop the syncKey (NOT just enabled) so reconnect is a fresh PAIR, never a one-click return
    /// to a bucket that may still carry the marker. Backend coords kept for easy re-pairing.
    private func clearLink() {
        var cfg = config
        cfg.syncKey = ""
        cfg.enabled = false
        SyncConfigStore.save(cfg)
        config = cfg
        stopPolling()
    }

    /// The OTHER device stamped the bucket → self-unlink and tell the user. Guarded: if WE already
    /// cleared our link (our own in-flight pass saw our marker), do nothing → no false "peer" note.
    private func handlePeerUnlink() {
        guard config.isSyncable else { return }
        BuddyDiag.log("peer-unlinked")
        clearLink()
        peerUnlinked = true
    }

    private static func validKey(_ k: String) -> Bool { SyncConfig.isValidSyncKey(k) }

    // MARK: - Triggers
    /// Launch + every foreground: pull now + poll live so the other device's edits show up ~1.5s.
    func syncOnForeground() { requestSync(); startPolling() }
    /// Background: stop polling (no point, and saves battery/quota).
    func pauseSync() { stopPolling() }

    private func startPolling() {
        guard config.isSyncable, pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.requestSync() }
        }
    }
    private func stopPolling() { pollTimer?.invalidate(); pollTimer = nil }

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
        // .resolved: cloud pairings re-read url/key from BuddyCloud each pass, so a
        // rotated hosted key takes effect on the next app update without re-pairing.
        let live = config.resolved
        guard let store, live.isSyncable,
              let cas = SupabaseCASStore(url: live.backendUrl, anonKey: live.anonKey,
                                         syncKey: live.syncKey, device: "ios")
        else { return }
        let key = SyncIdentity.ownerId(for: config.syncKey)   // M2: hash, not the raw key
        let local = store.snapshot()
        do {
            let res = try await BuddySync.syncOnce(store: cas, key: key, local: local)
            if res.unlinked && !unlinking { handlePeerUnlink(); return }   // peer dissolved the link
            if res.ok {
                // Adopt ONLY when the pass actually changed something for us. On a noop
                // pass where local already equals the remote content, re-adopting would
                // rewrite state + disk every 1.5s poll for nothing (UI jitter, IO churn) —
                // mirrors the Mac's "only re-apply when our local copy is behind remote".
                if let merged = res.merged,
                   !(res.noop && BuddySync.contentKey(local) == BuddySync.contentKey(merged)) {
                    store.adopt(merged)
                }
                lastSyncedAt = Date()
                lastError = nil
                if !res.noop {
                    BuddyDiag.log("sync", ["pushed": res.pushed, "pulled": res.pulled,
                                           "v": res.version, "attempts": res.attempts])
                }
            } else if res.degraded {
                // The OTHER device is on a NEWER format this build can't read — this is NOT a
                // transient conflict, it's "you must update". Say so plainly; a "will retry"
                // message would tell the incident's victim (the old device) to just wait
                // forever (review 2026-07-19).
                lastError = "Update Buddy to keep syncing with your Mac"
                BuddyDiag.log("sync-degraded")
            } else {
                // Do NOT stamp a reassuring lastSyncedAt on failure — retries were exhausted.
                lastError = "Sync failed (server conflict — will retry)"
                BuddyDiag.log("sync-conflict")
            }
        } catch {
            lastError = error.localizedDescription
            BuddyDiag.log("sync-error", ["err": String(error.localizedDescription.prefix(120))])
        }
    }
}
