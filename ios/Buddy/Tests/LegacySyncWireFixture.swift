// Frozen from 4535309 for older-iPhone serialization regression coverage.
import Foundation
@testable import Buddy

private let MS: Double = 1000

struct LegacySyncWire: Codable {
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

    // `ord` is the planner order the OLD positional id (h-<date>-<i>) used to imply. It must
    // round-trip: dropping it here would silently strip the Mac's ordering on every iOS pass.
    struct HistItem: Codable {
        var id: String; var text: String; var done: Bool; var ord: Int?
        init(id: String, text: String, done: Bool, ord: Int? = nil) {
            self.id = id; self.text = text; self.done = done; self.ord = ord
        }
        enum CodingKeys: String, CodingKey { case id, text, done, ord }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id   = (try? c.decode(String.self, forKey: .id)) ?? ""
            text = (try? c.decode(String.self, forKey: .text)) ?? ""
            done = (try? c.decode(Bool.self, forKey: .done)) ?? false
            ord  = (try? c.decodeIfPresent(Int.self, forKey: .ord)) ?? nil
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(text, forKey: .text)
            try c.encode(done, forKey: .done); try c.encodeIfPresent(ord, forKey: .ord)
        }
    }

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
    // id → {v, t}: version at which a rollover archived the id as done. `t` is ms on BOTH
    // platforms and takes NO seconds↔ms conversion (see DoneMark).
    var doneTombs: [String: DoneMark]
    var erasedAt: Double?               // epoch ms
    var syncNotice: SyncNotice?         // "N tasks moved to Future" banner (synced, dismissible)
    var unlinkedAt: Double?             // epoch ms — mutual-unlink marker (dissolves the link)
    var extras: [String: JSONValue] = [:]   // doneWordBag / pinned / restartStash / future fields

    // Tolerant decode: a missing key must NEVER throw and kill a sync pass. Swift's
    // synthesized decoder throws keyNotFound even for properties that HAVE a default,
    // so decode every field defensively. Unknown keys land in `extras` — EXCEPT the
    // E2E envelope keys (enc/iv/ct), which are listed as known-but-not-decoded so a
    // hybrid blob's stale envelope is DROPPED, never re-emitted through extras
    // (mirrors the Mac's DROP_WIRE_KEYS).
    static let knownKeys: Set<String> = ["version", "savedAt", "today", "history",
                                         "deferred", "settings", "tombstones", "doneTombs", "erasedAt",
                                         "syncNotice", "unlinkedAt", "enc", "iv", "ct"]
    private enum CodingKeys: String, CodingKey {
        case version, savedAt, today, history, deferred, settings, tombstones, doneTombs, erasedAt, syncNotice, unlinkedAt
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
        doneTombs  = BuddyMerge.sanitizeMarks((try? c.decodeIfPresent([String: JSONValue].self, forKey: .doneTombs)) ?? nil)
        erasedAt   = (try? c.decodeIfPresent(Double.self, forKey: .erasedAt)) ?? nil
        syncNotice = SyncNotice.sanitized((try? c.decodeIfPresent(SyncNotice.self, forKey: .syncNotice)) ?? nil)
        unlinkedAt = (try? c.decodeIfPresent(Double.self, forKey: .unlinkedAt)) ?? nil
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
        try c.encode(doneTombs, forKey: .doneTombs)
        try c.encodeIfPresent(erasedAt, forKey: .erasedAt)
        try c.encodeIfPresent(SyncNotice.sanitized(syncNotice), forKey: .syncNotice)
        try c.encodeIfPresent(unlinkedAt, forKey: .unlinkedAt)
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
                     items: d.items.map { HistItem(id: $0.id, text: $0.text, done: $0.done, ord: $0.ord) },
                     extras: d.extras) }
        deferred = s.deferred.map { Deferred(id: $0.id, text: $0.text, wake: $0.wake,
                                             sent: $0.sent, sentTid: $0.sentTid, v: $0.v,
                                             extras: $0.extras) }
        settings = s.settings
        tombstones = s.tombstones.mapValues { $0 * MS }
        doneTombs = s.doneTombs                          // already ms — no conversion (see DoneMark)
        erasedAt = s.erasedAt.map { $0 * MS }
        syncNotice = SyncNotice.sanitized(s.syncNotice)   // counts, not timestamps — no ms conversion
        unlinkedAt = s.unlinkedAt.map { $0 * MS }
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
                        items: $0.items.map { DayItem(id: $0.id, text: $0.text, done: $0.done, ord: $0.ord) },
                        extras: $0.extras) },
            deferred: deferred.map { DeferredTask(id: $0.id, text: $0.text, wake: $0.wake,
                                                  sent: $0.sent, sentTid: $0.sentTid, v: $0.v,
                                                  extras: $0.extras) },
            settings: settings,
            tombstones: tombstones.mapValues { $0 / MS },
            doneTombs: doneTombs,                        // already ms — no conversion (see DoneMark)
            erasedAt: erasedAt.map { $0 / MS },
            savedAt: savedAt / MS,
            syncNotice: SyncNotice.sanitized(syncNotice),
            unlinkedAt: unlinkedAt.map { $0 / MS },
            extras: extras
        )
    }
}
