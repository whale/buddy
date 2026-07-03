import XCTest
@testable import Buddy

// GOLDEN cross-decode (P0.5). Pure unit tests — no network, always run.
//
// These pin the Mac↔iOS wire boundary against a blob shaped EXACTLY like the Mac's
// serialize() output (dist/index.html): epoch-MILLISECOND timestamps, settings with
// ONLY { celebrate, reserveSpace } (no historyDays), `pinned` present, item `src`/`doneAt`
// null, plus a `restartStash` key iOS doesn't model. If iOS can't decode this, Mac→iOS
// sync silently dies on every pull — which is exactly what shipped before the B1 fix.
final class SyncGoldenDecodeTests: XCTestCase {

    // Verbatim shape of what dist/index.html serialize() writes (values chosen for the assertions).
    private let macBlobJSON = """
    {
      "version": 1,
      "savedAt": 1750000000000,
      "today": {
        "date": "2026-06-21",
        "morningDone": true,
        "items": [
          { "id": "m1", "text": "made on Mac", "state": "focused", "src": null, "doneAt": null, "v": 3 },
          { "id": "m2", "text": "done on Mac", "state": "done", "src": null, "doneAt": 1750000005000, "v": 2 }
        ]
      },
      "history": [
        { "date": "2026-06-20", "weekday": "Friday", "items": [ { "id": "h-2026-06-20-0", "text": "yesterday", "done": true } ] }
      ],
      "deferred": [ { "id": "d1", "text": "later", "wake": "2026-06-25" } ],
      "settings": { "celebrate": 80, "reserveSpace": false },
      "pinned": true,
      "tombstones": { "gone": 1750000004000 },
      "erasedAt": null,
      "restartStash": null
    }
    """

    // THE B1 GUARD: a real Mac blob (no historyDays) must decode, not throw.
    func testDecodesMacBlobWithoutHistoryDays() throws {
        let data = Data(macBlobJSON.utf8)
        let wire = try JSONDecoder().decode(SyncWire.self, from: data)   // must NOT throw
        let s = wire.toSnapshot()

        // ms → s conversion survived
        XCTAssertEqual(s.savedAt, 1_750_000_000, accuracy: 0.5)
        XCTAssertEqual(s.today?.items.first(where: { $0.id == "m2" })?.doneAt?.timeIntervalSince1970 ?? 0,
                       1_750_000_005, accuracy: 0.5)

        // items decoded with state + version
        XCTAssertEqual(s.today?.items.count, 2)
        XCTAssertEqual(s.today?.items.first?.state, .focused)
        XCTAssertEqual(s.today?.items.first?.v, 3)
        XCTAssertEqual(s.today?.morningDone, true)

        // history + deferred + tombstones survived
        XCTAssertEqual(s.history.first?.items.first?.text, "yesterday")
        XCTAssertEqual(s.deferred.first?.wake, "2026-06-25")
        XCTAssertEqual(s.tombstones["gone"] ?? 0, 1_750_000_004, accuracy: 0.5)

        // settings decoded; historyDays DEFAULTED (the Mac never sends it) — the B1 fix
        XCTAssertEqual(s.settings?.celebrate, 80)
        XCTAssertEqual(s.settings?.historyDays, BuddySettings.default.historyDays)
        XCTAssertEqual(s.settings?.reserveSpace, false)
    }

    // A blob with NO settings object at all still decodes (settings → nil).
    func testDecodesBlobWithNoSettings() throws {
        let json = """
        { "version":1, "savedAt":1750000000000, "today":{"date":"2026-06-21","morningDone":false,"items":[]},
          "history":[], "deferred":[], "tombstones":{}, "erasedAt":null }
        """
        let wire = try JSONDecoder().decode(SyncWire.self, from: Data(json.utf8))
        XCTAssertNil(wire.toSnapshot().settings)
    }

    // Reverse direction: an iOS-authored snapshot serializes to the ms wire the Mac reads.
    func testIOSSnapshotSerializesToMsWire() throws {
        let snap = SyncSnapshot(
            today: TodayState(date: "2026-06-21",
                              items: [BuddyTask(id: "i1", text: "from iOS", state: .done,
                                                doneAt: Date(timeIntervalSince1970: 1_750_000_010), v: 4)],
                              morningDone: true),
            history: [], deferred: [], settings: .default, tombstones: ["t": 1_750_000_003], erasedAt: nil,
            savedAt: 1_750_000_000)
        let wire = SyncWire(snap)
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(wire)) as! [String: Any]

        XCTAssertEqual(obj["savedAt"] as? Double, 1_750_000_000_000)          // seconds → ms
        let today = obj["today"] as! [String: Any]
        let item = (today["items"] as! [[String: Any]]).first!
        XCTAssertEqual(item["doneAt"] as? Double, 1_750_000_010_000)          // ms on the wire
        let tomb = obj["tombstones"] as! [String: Any]
        XCTAssertEqual(tomb["t"] as? Double, 1_750_000_003_000)               // ms on the wire
    }
}
