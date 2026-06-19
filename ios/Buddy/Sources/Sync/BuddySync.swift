import Foundation

// MARK: - BuddySync (sync step 5, iOS) — CAS-on-client loop, Swift mirror of dist/index.html.
//
// The merge runs on the CLIENT (BuddyMerge); the server is a dumb compare-and-swap
// store. Each pass: pull → merge(local, remote) → CAS push → retry on version conflict.
//
// WIRE FORMAT: the on-the-wire blob uses epoch MILLISECONDS (the Mac's native unit).
// iOS keeps time in seconds (Date.timeIntervalSince1970); SyncWire converts s↔ms at the
// boundary so a Mac blob and an iOS blob are directly comparable once decoded into the
// local domain. (This is the timestamp-unit fix; the Mac needs no change.)

// MARK: - Store contract (mirror of makeFakeCASStore / the buddy_push SQL)
struct PullResult { let blob: SyncSnapshot?; let version: Int }   // version 0 / blob nil if absent
struct PushResult { let ok: Bool; let blob: SyncSnapshot?; let version: Int }

protocol CASStore {
    func pull(_ key: String) async throws -> PullResult
    func push(_ key: String, blob: SyncSnapshot, expected: Int) async throws -> PushResult
}

struct SyncResult {
    var ok: Bool
    var pushed = false
    var pulled = false
    var noop = false
    var version = 0
    var attempts = 0
    var merged: SyncSnapshot?   // the snapshot the caller should adopt as local truth
}

enum BuddySync {
    static let maxRetry = 5

    static func blobIsEmpty(_ b: SyncSnapshot?) -> Bool {
        guard let b = b else { return true }
        return (b.today?.items.count ?? 0) == 0 && b.history.isEmpty && b.deferred.isEmpty
            && b.tombstones.isEmpty && b.erasedAt == nil
    }

    /// Content fingerprint that IGNORES savedAt — so an unchanged re-sync is a no-op
    /// (prevents two idle devices ping-ponging version bumps).
    static func contentKey(_ b: SyncSnapshot?) -> String {
        guard let b = b else { return "" }
        var wire = SyncWire(b)
        wire.savedAt = 0
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        return (try? String(data: enc.encode(wire), encoding: .utf8) ?? "") ?? ""
    }

    /// One sync pass. Returns what happened + the snapshot the caller should adopt.
    static func syncOnce(store: CASStore, key: String, local: SyncSnapshot) async throws -> SyncResult {
        let remote = try await store.pull(key)

        // Empty-over-full guard / scanner-pulls-first: a fresh empty device adopts the
        // remote rather than pushing nothing over it.
        if blobIsEmpty(local) && !blobIsEmpty(remote.blob) {
            return SyncResult(ok: true, pulled: true, version: remote.version, merged: remote.blob)
        }

        guard var merged = BuddyMerge.merge(local, remote.blob) else { return SyncResult(ok: false) }

        // Nothing new vs remote → adopt remote, don't churn the version.
        if contentKey(merged) == contentKey(remote.blob) {
            return SyncResult(ok: true, noop: true, version: remote.version, merged: remote.blob ?? merged)
        }

        var expected = remote.version
        for attempt in 0..<maxRetry {
            let res = try await store.push(key, blob: merged, expected: expected)
            if res.ok {
                return SyncResult(ok: true, pushed: true, version: res.version, attempts: attempt + 1, merged: merged)
            }
            // Someone wrote between pull and push → fold their blob in and retry CAS.
            merged = BuddyMerge.merge(merged, res.blob) ?? merged
            if res.version > 0 { expected = res.version }   // keep old expected on a malformed version
        }
        return SyncResult(ok: false)
    }
}

// MARK: - In-memory CAS store — reference implementation of the server contract, for tests.
actor InMemoryCASStore: CASStore {
    private var rows: [String: (blob: SyncSnapshot, version: Int)] = [:]

    init(seed: (key: String, blob: SyncSnapshot, version: Int)? = nil) {
        if let s = seed { rows[s.key] = (s.blob, s.version) }
    }

    func pull(_ key: String) -> PullResult {
        if let r = rows[key] { return PullResult(blob: r.blob, version: r.version) }
        return PullResult(blob: nil, version: 0)
    }

    func push(_ key: String, blob: SyncSnapshot, expected: Int) -> PushResult {
        if let cur = rows[key] {
            if expected == cur.version {
                rows[key] = (blob, cur.version + 1)
                return PushResult(ok: true, blob: blob, version: cur.version + 1)
            }
            return PushResult(ok: false, blob: cur.blob, version: cur.version)
        }
        if expected != 0 { return PushResult(ok: false, blob: nil, version: 0) }
        rows[key] = (blob, 1)
        return PushResult(ok: true, blob: blob, version: 1)
    }

    func currentVersion(_ key: String) -> Int { rows[key]?.version ?? 0 }
    func currentBlob(_ key: String) -> SyncSnapshot? { rows[key]?.blob }
}

// MARK: - SyncWire — the Mac-compatible JSON blob (epoch ms), with s↔ms conversion.
private let MS = 1000.0

struct SyncWire: Codable {
    struct Item: Codable { var id: String; var text: String; var state: String; var src: String?; var doneAt: Double?; var v: Int }
    struct Today: Codable { var date: String; var morningDone: Bool; var items: [Item] }
    struct HistItem: Codable { var id: String; var text: String; var done: Bool }
    struct HistDay: Codable { var date: String; var weekday: String; var items: [HistItem] }
    struct Deferred: Codable { var id: String; var text: String; var wake: String }

    var version = 1
    var savedAt: Double                 // epoch ms
    var today: Today?
    var history: [HistDay]
    var deferred: [Deferred]
    var settings: BuddySettings?
    var pinned = false
    var tombstones: [String: Double]    // id → epoch ms
    var erasedAt: Double?               // epoch ms

    // snapshot (seconds) → wire (ms)
    init(_ s: SyncSnapshot) {
        savedAt = s.savedAt * MS
        today = s.today.map { t in
            Today(date: t.date, morningDone: t.morningDone,
                  items: t.items.map { Item(id: $0.id, text: $0.text, state: $0.state.rawValue,
                                            src: nil, doneAt: $0.doneAt.map { $0.timeIntervalSince1970 * MS }, v: $0.v) })
        }
        history = s.history.map { d in HistDay(date: d.date, weekday: d.weekday,
                     items: d.items.map { HistItem(id: $0.id, text: $0.text, done: $0.done) }) }
        deferred = s.deferred.map { Deferred(id: $0.id, text: $0.text, wake: $0.wake) }
        settings = s.settings
        tombstones = s.tombstones.mapValues { $0 * MS }
        erasedAt = s.erasedAt.map { $0 * MS }
    }

    // wire (ms) → snapshot (seconds)
    func toSnapshot() -> SyncSnapshot {
        SyncSnapshot(
            today: today.map { t in
                TodayState(date: t.date, items: t.items.map {
                    BuddyTask(id: $0.id, text: $0.text, state: TaskState(rawValue: $0.state) ?? .neutral,
                              doneAt: $0.doneAt.map { Date(timeIntervalSince1970: $0 / MS) }, v: $0.v)
                }, morningDone: t.morningDone)
            },
            history: history.map { Day(date: $0.date, weekday: $0.weekday,
                        items: $0.items.map { DayItem(id: $0.id, text: $0.text, done: $0.done) }) },
            deferred: deferred.map { DeferredTask(id: $0.id, text: $0.text, wake: $0.wake) },
            settings: settings,
            tombstones: tombstones.mapValues { $0 / MS },
            erasedAt: erasedAt.map { $0 / MS },
            savedAt: savedAt / MS
        )
    }
}
