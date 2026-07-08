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

    // MARK: - Content key (byte-parity mirror of the Mac's blobContentKey)
    //
    // Content fingerprint that IGNORES savedAt — an unchanged re-sync is a no-op
    // (prevents two idle devices ping-ponging version bumps). Also the tie-break for
    // "who's newer" in merge(), so it MUST produce the SAME string on both platforms
    // for the same logical wire content, or the two devices pick different winners
    // and never converge.
    //
    // Projected to the CANONICAL shape both devices agree on:
    //   (a) object key order        → CanonicalJSON sorts keys
    //   (b) array order             → today/deferred sorted by id, history date-desc
    //   (c) peer-incompatible bits  → EXCLUDED: savedAt, pinned, item src/doneWord,
    //       deferred v (an older peer strips it and it never changes without
    //       sent/sentTid changing too), restartStash, all extras, settings.historyDays.
    // Timestamps in the key are epoch MILLISECONDS (doneAt rounded), like the Mac.

    private static let msFactor = 1000.0

    /// The Mac's _ckItem: { id, text, state, v, doneAt?(ms, rounded) } → canonical string.
    static func ckItem(_ i: BuddyTask) -> String { CanonicalJSON.canonical(itemValue(i)) }

    /// The Mac's _ckDef: { id, text, wake, sent?(only true), sentTid?(only when sent) }.
    /// NOTE: v and an unset sent are EXCLUDED from the projection (see header comment).
    static func ckDef(_ d: DeferredTask) -> String { CanonicalJSON.canonical(defValue(d)) }

    static func contentKey(_ b: SyncSnapshot?) -> String {
        guard let b = b else { return "" }
        // today items → _ckItem, sorted by id (JS string order)
        let items = (b.today?.items ?? [])
            .sorted { CanonicalJSON.compare($0.id, $1.id) < 0 }
            .map { itemValue($0) }
        // deferred → _ckDef, sorted by id
        let defs = b.deferred
            .sorted { CanonicalJSON.compare($0.id, $1.id) < 0 }
            .map { defValue($0) }
        // history → projected to the shared fields, sorted date-desc
        let hist = b.history
            .sorted { CanonicalJSON.compare($0.date, $1.date) > 0 }
            .map { r in
                JSONValue.object([
                    "date": .string(r.date), "weekday": .string(r.weekday),
                    "items": .array(r.items.map { .object([
                        "id": .string($0.id), "text": .string($0.text), "done": .bool($0.done),
                    ]) }),
                ])
            }
        var tomb = [String: JSONValue]()
        for (id, t) in b.tombstones { tomb[id] = .number(t * msFactor) }
        let s: [String: JSONValue] = [
            "celebrate": b.settings.map { .int(Int64($0.celebrate)) } ?? .null,
            "reserveSpace": .bool(b.settings?.reserveSpace ?? false),
        ]
        return CanonicalJSON.canonical(.object([
            "td": b.today.map { .string($0.date) } ?? .null,
            "m": .bool(b.today?.morningDone ?? false),
            "t": .array(items), "h": .array(hist), "d": .array(defs),
            "tomb": .object(tomb),
            "e": b.erasedAt.map { .number($0 * msFactor) } ?? .null,
            "s": .object(s),
        ]))
    }

    // JSONValue builders sharing the exact _ckItem/_ckDef projections above.
    private static func itemValue(_ i: BuddyTask) -> JSONValue {
        var o: [String: JSONValue] = [
            "id": .string(i.id), "text": .string(i.text),
            "state": .string(i.state.rawValue), "v": .int(Int64(i.v < 1 ? 1 : i.v)),
        ]
        if let doneAt = i.doneAt {
            o["doneAt"] = .number((doneAt.timeIntervalSince1970 * msFactor).rounded())
        }
        return .object(o)
    }
    private static func defValue(_ d: DeferredTask) -> JSONValue {
        var o: [String: JSONValue] = [
            "id": .string(d.id), "text": .string(d.text), "wake": .string(d.wake),
        ]
        if d.sent == true {
            o["sent"] = .bool(true)
            if let tid = d.sentTid { o["sentTid"] = .string(tid) }
        }
        return .object(o)
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

        // Nothing new vs remote → adopt remote, don't churn the version. The caller
        // (SyncEngine) additionally skips the adopt when local == remote content, so an
        // idle 1.5s poll never rewrites state/disk (mirrors the Mac's applyWire skip).
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
// Every level carries an `extras` bag: keys outside the KNOWN set are captured at
// decode and re-emitted (extras first, known keys win) at encode, so a newer peer's
// fields survive an iOS round-trip (version-skew safety). At the TOP level the known
// set is deliberately SMALLER than the Mac's KNOWN_WIRE_KEYS: doneWordBag / pinned /
// restartStash are Mac concepts iOS doesn't model, so they land in extras and ride
// through untouched — exactly what we want.
private let MS = 1000.0

struct SyncWire: Codable {
    struct Item: Codable {
        var id: String; var text: String; var state: String; var doneAt: Double?; var v: Int
        var extras: [String: JSONValue] = [:]   // Mac's src/doneWord + future fields

        static let knownKeys: Set<String> = ["id", "text", "state", "doneAt", "v"]
        enum CodingKeys: String, CodingKey { case id, text, state, doneAt, v }
        init(id: String, text: String, state: String, doneAt: Double?, v: Int,
             extras: [String: JSONValue] = [:]) {
            self.id = id; self.text = text; self.state = state; self.doneAt = doneAt; self.v = v
            self.extras = extras
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id     = try c.decode(String.self, forKey: .id)
            text   = (try? c.decode(String.self, forKey: .text)) ?? ""
            state  = (try? c.decode(String.self, forKey: .state)) ?? "neutral"
            doneAt = (try? c.decodeIfPresent(Double.self, forKey: .doneAt)) ?? nil
            v      = (try? c.decodeIfPresent(Int.self, forKey: .v)) ?? 1
            extras = decodeExtras(from: decoder, known: Self.knownKeys)
        }
        func encode(to encoder: Encoder) throws {
            var dyn = encoder.container(keyedBy: AnyCodingKey.self)
            for (k, val) in extras { try dyn.encode(val, forKey: AnyCodingKey(k)) }
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(text, forKey: .text)
            try c.encode(state, forKey: .state)
            try c.encodeIfPresent(doneAt, forKey: .doneAt)
            try c.encode(v, forKey: .v)
        }
    }

    struct Today: Codable {
        var date: String; var morningDone: Bool; var items: [Item]
        var extras: [String: JSONValue] = [:]

        static let knownKeys: Set<String> = ["date", "morningDone", "items"]
        enum CodingKeys: String, CodingKey { case date, morningDone, items }
        init(date: String, morningDone: Bool, items: [Item], extras: [String: JSONValue] = [:]) {
            self.date = date; self.morningDone = morningDone; self.items = items; self.extras = extras
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date        = (try? c.decode(String.self, forKey: .date)) ?? ""
            morningDone = (try? c.decodeIfPresent(Bool.self, forKey: .morningDone)) ?? false
            items       = (try? c.decode([Item].self, forKey: .items)) ?? []
            extras      = decodeExtras(from: decoder, known: Self.knownKeys)
        }
        func encode(to encoder: Encoder) throws {
            var dyn = encoder.container(keyedBy: AnyCodingKey.self)
            for (k, val) in extras { try dyn.encode(val, forKey: AnyCodingKey(k)) }
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(date, forKey: .date)
            try c.encode(morningDone, forKey: .morningDone)
            try c.encode(items, forKey: .items)
        }
    }

    struct HistItem: Codable { var id: String; var text: String; var done: Bool }

    struct HistDay: Codable {
        var date: String; var weekday: String; var items: [HistItem]
        var extras: [String: JSONValue] = [:]

        static let knownKeys: Set<String> = ["date", "weekday", "items"]
        enum CodingKeys: String, CodingKey { case date, weekday, items }
        init(date: String, weekday: String, items: [HistItem], extras: [String: JSONValue] = [:]) {
            self.date = date; self.weekday = weekday; self.items = items; self.extras = extras
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date    = (try? c.decode(String.self, forKey: .date)) ?? ""
            weekday = (try? c.decode(String.self, forKey: .weekday)) ?? ""
            items   = (try? c.decode([HistItem].self, forKey: .items)) ?? []
            extras  = decodeExtras(from: decoder, known: Self.knownKeys)
        }
        func encode(to encoder: Encoder) throws {
            var dyn = encoder.container(keyedBy: AnyCodingKey.self)
            for (k, val) in extras { try dyn.encode(val, forKey: AnyCodingKey(k)) }
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(date, forKey: .date)
            try c.encode(weekday, forKey: .weekday)
            try c.encode(items, forKey: .items)
        }
    }

    struct Deferred: Codable {
        var id: String; var text: String; var wake: String
        var sent: Bool? = nil; var sentTid: String? = nil; var v: Int = 1
        var extras: [String: JSONValue] = [:]

        static let knownKeys: Set<String> = ["id", "text", "wake", "sent", "sentTid", "v"]
        enum CodingKeys: String, CodingKey { case id, text, wake, sent, sentTid, v }
        init(id: String, text: String, wake: String, sent: Bool? = nil, sentTid: String? = nil,
             v: Int = 1, extras: [String: JSONValue] = [:]) {
            self.id = id; self.text = text; self.wake = wake
            self.sent = sent; self.sentTid = sentTid; self.v = v; self.extras = extras
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id   = try c.decode(String.self, forKey: .id)
            text = (try? c.decode(String.self, forKey: .text)) ?? ""
            wake = (try? c.decode(String.self, forKey: .wake)) ?? ""
            let s = (try? c.decodeIfPresent(Bool.self, forKey: .sent)) ?? nil
            if s == true {
                sent = true
                sentTid = (try? c.decodeIfPresent(String.self, forKey: .sentTid)) ?? nil
            } else {
                sent = nil; sentTid = nil
            }
            v = (try? c.decodeIfPresent(Int.self, forKey: .v)) ?? 1   // tolerant: pre-v rows default 1
            extras = decodeExtras(from: decoder, known: Self.knownKeys)
        }
        func encode(to encoder: Encoder) throws {
            var dyn = encoder.container(keyedBy: AnyCodingKey.self)
            for (k, val) in extras { try dyn.encode(val, forKey: AnyCodingKey(k)) }
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(text, forKey: .text)
            try c.encode(wake, forKey: .wake)
            if sent == true {
                try c.encode(true, forKey: .sent)
                try c.encodeIfPresent(sentTid, forKey: .sentTid)
            }
            try c.encode(v, forKey: .v)
        }
    }

    var version = 1
    var savedAt: Double                 // epoch ms
    var today: Today?
    var history: [HistDay]
    var deferred: [Deferred]
    var settings: BuddySettings?
    var tombstones: [String: Double]    // id → epoch ms
    var erasedAt: Double?               // epoch ms
    var extras: [String: JSONValue] = [:]   // doneWordBag / pinned / restartStash / future fields

    // Tolerant decode: a missing key must NEVER throw and kill a sync pass. Swift's
    // synthesized decoder throws keyNotFound even for properties that HAVE a default,
    // so decode every field defensively. Unknown keys land in `extras`.
    static let knownKeys: Set<String> = ["version", "savedAt", "today", "history",
                                         "deferred", "settings", "tombstones", "erasedAt"]
    private enum CodingKeys: String, CodingKey {
        case version, savedAt, today, history, deferred, settings, tombstones, erasedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version    = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        savedAt    = (try? c.decodeIfPresent(Double.self, forKey: .savedAt)) ?? 0
        today      = (try? c.decodeIfPresent(Today.self, forKey: .today)) ?? nil
        history    = (try? c.decodeIfPresent([HistDay].self, forKey: .history)) ?? []
        deferred   = (try? c.decodeIfPresent([Deferred].self, forKey: .deferred)) ?? []
        settings   = (try? c.decodeIfPresent(BuddySettings.self, forKey: .settings)) ?? nil
        tombstones = (try? c.decodeIfPresent([String: Double].self, forKey: .tombstones)) ?? [:]
        erasedAt   = (try? c.decodeIfPresent(Double.self, forKey: .erasedAt)) ?? nil
        extras     = decodeExtras(from: decoder, known: Self.knownKeys)
    }
    // Extras first, known keys win — mirrors the Mac's `{ ...(state.extras||{}), version:1, … }`.
    func encode(to encoder: Encoder) throws {
        var dyn = encoder.container(keyedBy: AnyCodingKey.self)
        for (k, val) in extras { try dyn.encode(val, forKey: AnyCodingKey(k)) }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(savedAt, forKey: .savedAt)
        try c.encodeIfPresent(today, forKey: .today)
        try c.encode(history, forKey: .history)
        try c.encode(deferred, forKey: .deferred)
        try c.encodeIfPresent(settings, forKey: .settings)
        try c.encode(tombstones, forKey: .tombstones)
        try c.encodeIfPresent(erasedAt, forKey: .erasedAt)
    }

    // snapshot (seconds) → wire (ms)
    init(_ s: SyncSnapshot) {
        savedAt = s.savedAt * MS
        today = s.today.map { t in
            Today(date: t.date, morningDone: t.morningDone,
                  items: t.items.map { Item(id: $0.id, text: $0.text, state: $0.state.rawValue,
                                            doneAt: $0.doneAt.map { $0.timeIntervalSince1970 * MS },
                                            v: $0.v, extras: $0.extras) },
                  extras: t.extras)
        }
        history = s.history.map { d in HistDay(date: d.date, weekday: d.weekday,
                     items: d.items.map { HistItem(id: $0.id, text: $0.text, done: $0.done) },
                     extras: d.extras) }
        deferred = s.deferred.map { Deferred(id: $0.id, text: $0.text, wake: $0.wake,
                                             sent: $0.sent, sentTid: $0.sentTid, v: $0.v,
                                             extras: $0.extras) }
        settings = s.settings
        tombstones = s.tombstones.mapValues { $0 * MS }
        erasedAt = s.erasedAt.map { $0 * MS }
        extras = s.extras
    }

    // wire (ms) → snapshot (seconds)
    func toSnapshot() -> SyncSnapshot {
        SyncSnapshot(
            today: today.map { t in
                TodayState(date: t.date, items: t.items.map {
                    BuddyTask(id: $0.id, text: $0.text, state: TaskState(rawValue: $0.state) ?? .neutral,
                              doneAt: $0.doneAt.map { Date(timeIntervalSince1970: $0 / MS) },
                              v: $0.v, extras: $0.extras)
                }, morningDone: t.morningDone, extras: t.extras)
            },
            history: history.map { Day(date: $0.date, weekday: $0.weekday,
                        items: $0.items.map { DayItem(id: $0.id, text: $0.text, done: $0.done) },
                        extras: $0.extras) },
            deferred: deferred.map { DeferredTask(id: $0.id, text: $0.text, wake: $0.wake,
                                                  sent: $0.sent, sentTid: $0.sentTid, v: $0.v,
                                                  extras: $0.extras) },
            settings: settings,
            tombstones: tombstones.mapValues { $0 / MS },
            erasedAt: erasedAt.map { $0 / MS },
            savedAt: savedAt / MS,
            extras: extras
        )
    }
}
