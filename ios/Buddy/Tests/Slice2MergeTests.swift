import XCTest
@testable import Buddy

// Sync Slice 2 — deterministic, symmetric cross-device merge. Mirrors the Mac's
// mergeTest() cases 15–21 (dist/index.html) plus the contentKey parity guards.
// The invariant under test: merge(a,b) === merge(b,a), byte-for-byte, so the Mac
// and the iPhone always agree on a single winner and converge instead of each
// "winning" locally (the 0.3.17 flash-then-revert / overwrite bug).
final class Slice2MergeTests: XCTestCase {

    // MARK: - builders
    private func snap(today: TodayState? = TodayState(date: "2026-06-19", items: []),
                      history: [Day] = [], deferred: [DeferredTask] = [],
                      settings: BuddySettings? = nil, tombstones: [String: Double] = [:],
                      erasedAt: Double? = nil, savedAt: Double = 1000,
                      extras: [String: JSONValue] = [:]) -> SyncSnapshot {
        SyncSnapshot(today: today, history: history, deferred: deferred,
                     settings: settings, tombstones: tombstones, erasedAt: erasedAt,
                     savedAt: savedAt, extras: extras)
    }
    private func item(_ id: String, _ text: String, _ st: TaskState = .neutral,
                      _ v: Int = 1, _ doneAt: Date? = nil) -> BuddyTask {
        BuddyTask(id: id, text: text, state: st, doneAt: doneAt, v: v)
    }

    /// Full-fidelity canonical form of a merged snapshot (via the wire codec), including
    /// array ORDER — the strongest possible "these two results are identical" compare.
    private func fullCanon(_ s: SyncSnapshot?) -> String {
        guard let s = s else { return "nil" }
        let data = try! JSONEncoder().encode(SyncWire(s))
        let v = try! JSONDecoder().decode(JSONValue.self, from: data)
        return CanonicalJSON.canonical(v)
    }

    // MARK: - 15. Full symmetry: merge(a,b) === merge(b,a), content AND order.
    func testMergeIsFullySymmetric() {
        let A = snap(today: TodayState(date: "2026-06-19", items: [item("t1","A-edit",.neutral,2), item("t2","keep")]), savedAt: 2000)
        let B = snap(today: TodayState(date: "2026-06-19", items: [item("t1","old"), item("t2","B-edit",.neutral,2)]), savedAt: 1900)
        let bigA = snap(today: TodayState(date: "2026-06-19", items: (1...6).map { item("a\($0)", "task \($0)") }), savedAt: 2000)
        let bigB = snap(today: TodayState(date: "2026-06-19", items: [item("b7","seven"), item("b8","eight")]), savedAt: 1900)
        let dupA = snap(today: TodayState(date: "2026-06-19", items: [item("m1","Check the bill"), item("dn","archived",.done,1, Date(timeIntervalSince1970: 1))]), savedAt: 2000)
        let dupB = snap(today: TodayState(date: "2026-06-19", items: [item("i1","Check the bill")]), savedAt: 1900)
        // Equal savedAt — the content tie-break must decide identically on both sides.
        let tieA = snap(today: TodayState(date: "d", items: [item("s1","same-stamp A")]), savedAt: 1000)
        let tieB = snap(today: TodayState(date: "d", items: [item("s2","same-stamp B")]), savedAt: 1000)
        // Sent/deferred conflict + different-dates pair for good measure.
        let defA = snap(today: TodayState(date: "d", items: [item("n1","sent task")]),
                        deferred: [DeferredTask(id: "d1", text: "sent task", wake: "", sent: true, sentTid: "n1", v: 2)], savedAt: 1000)
        let defB = snap(today: TodayState(date: "d", items: []),
                        deferred: [DeferredTask(id: "d1", text: "sent task", wake: "", v: 1)], savedAt: 5000)
        let dayA = snap(today: TodayState(date: "2026-06-23", items: []), savedAt: 1000)
        let dayB = snap(today: TodayState(date: "2026-06-22", items: [item("y2","late edit",.neutral,3)], morningDone: true), savedAt: 9000)

        for (i, (p, q)) in [(A,B),(bigA,bigB),(dupA,dupB),(tieA,tieB),(defA,defB),(dayA,dayB)].enumerated() {
            XCTAssertEqual(fullCanon(BuddyMerge.merge(p, q)), fullCanon(BuddyMerge.merge(q, p)),
                           "fixture \(i): merge(a,b) != merge(b,a)")
        }
    }

    // MARK: - 16. "Sent to today!" survives a stale peer (THE revert bug), both directions.
    func testSentFlagBeatsStalePeerBothDirections() {
        let defA = snap(today: TodayState(date: "d", items: [item("n1","sent task")]),
                        deferred: [DeferredTask(id: "d1", text: "sent task", wake: "", sent: true, sentTid: "n1", v: 2)], savedAt: 1000)
        let defB = snap(today: TodayState(date: "d", items: []),
                        deferred: [DeferredTask(id: "d1", text: "sent task", wake: "", v: 1)], savedAt: 5000)
        for m in [BuddyMerge.merge(defA, defB), BuddyMerge.merge(defB, defA)] {
            let row = m?.deferred.first { $0.id == "d1" }
            XCTAssertEqual(row?.sent, true)
            XCTAssertEqual(row?.sentTid, "n1")
            XCTAssertTrue(m?.today?.items.contains { $0.id == "n1" } ?? false)
        }
    }

    // MARK: - 17. Undo (unsend) beats the peer's sent copy: higher v + tombstoned today id.
    func testUnsendBeatsPeerSentCopy() {
        let unA = snap(today: TodayState(date: "d", items: []),
                       deferred: [DeferredTask(id: "d2", text: "undone", wake: "", v: 3)],
                       tombstones: ["n2": 900], savedAt: 1000)
        let unB = snap(today: TodayState(date: "d", items: [item("n2","undone")]),
                       deferred: [DeferredTask(id: "d2", text: "undone", wake: "", sent: true, sentTid: "n2", v: 2)], savedAt: 5000)
        let m = BuddyMerge.merge(unB, unA)
        let d2 = m?.deferred.first { $0.id == "d2" }
        XCTAssertNotEqual(d2?.sent, true)
        XCTAssertNil(d2?.sentTid)
        XCTAssertFalse(m?.today?.items.contains { $0.id == "n2" } ?? true)
    }

    // MARK: - 18. A sent row whose Today copy didn't survive reconciles back to plain.
    func testOrphanedSentRowReconcilesToPlain() {
        let orA = snap(today: TodayState(date: "d", items: []),
                       deferred: [DeferredTask(id: "d3", text: "orphan", wake: "", sent: true, sentTid: "ghost", v: 2)], savedAt: 2000)
        let orB = snap(today: TodayState(date: "d", items: []), savedAt: 1000)
        let m = BuddyMerge.merge(orA, orB)
        let d3 = m?.deferred.first { $0.id == "d3" }
        XCTAssertNotNil(d3)
        XCTAssertNil(d3?.sent)
        XCTAssertNil(d3?.sentTid)
        XCTAssertEqual(d3?.v, 2)   // reconcile must NOT bump v
    }

    // MARK: - 19. The CALENDAR-later day is live even when the earlier day saved later;
    // the earlier-dated live list is archived, not dropped.
    func testCalendarLaterDayWinsLiveAndEarlierListIsArchived() {
        let dayA = snap(today: TodayState(date: "2026-06-23", items: []), savedAt: 1000)
        let dayB = snap(today: TodayState(date: "2026-06-22", items: [item("y2","late edit",.neutral,3)], morningDone: true), savedAt: 9000)
        for m in [BuddyMerge.merge(dayA, dayB), BuddyMerge.merge(dayB, dayA)] {
            XCTAssertEqual(m?.today?.date, "2026-06-23")
            XCTAssertEqual(m?.today?.items.count, 0)
            let rec = m?.history.first { $0.date == "2026-06-22" }
            XCTAssertEqual(rec?.items.first?.text, "late edit")
            XCTAssertEqual(rec?.items.first?.done, false)
            XCTAssertEqual(rec?.items.first?.id, "h-2026-06-22-0")   // Mac-stable positional id
        }
    }

    // MARK: - 21 + Slice 2: unknown fields pass through decode → merge → encode untouched
    // (top-level restartStash/doneWordBag/pinned, per-item, per-deferred, per-history-day,
    // and iOS-native settings.historyDays). Version-skew safety.
    func testUnknownFieldsRoundTripThroughWireAndMerge() throws {
        let macJSON = """
        {
          "version": 1, "savedAt": 2000000,
          "zzNewTopLevel": { "keep": true },
          "doneWordBag": ["Bam", "Yes"],
          "pinned": true,
          "restartStash": { "texts": ["stashed plan"], "date": "2026-06-19" },
          "today": { "date": "2026-06-21", "morningDone": false, "zzToday": 1,
                     "items": [ { "id": "u1", "text": "t", "state": "neutral", "v": 1,
                                  "zzItem": "ride", "src": null, "doneWord": "Boom" } ] },
          "history": [ { "date": "2026-06-20", "weekday": "Friday", "zzHist": 9,
                         "items": [ { "id": "h-2026-06-20-0", "text": "y", "done": true } ] } ],
          "deferred": [ { "id": "ud1", "text": "p", "wake": "", "v": 1, "zzDef": 7 } ],
          "settings": { "celebrate": 100, "reserveSpace": false, "historyDays": 14 },
          "tombstones": {}, "erasedAt": null
        }
        """
        let wire = try JSONDecoder().decode(SyncWire.self, from: Data(macJSON.utf8))
        let remote = wire.toSnapshot()
        // Merge against an older local snapshot, then re-encode — the Mac must get its
        // fields back exactly, even though iOS models none of them.
        let local = snap(today: TodayState(date: "2026-06-21", items: []), settings: .default, savedAt: 1000)
        let merged = try XCTUnwrap(BuddyMerge.merge(remote, local))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(SyncWire(merged))) as? [String: Any])

        XCTAssertEqual((obj["zzNewTopLevel"] as? [String: Any])?["keep"] as? Bool, true)
        XCTAssertEqual(obj["doneWordBag"] as? [String], ["Bam", "Yes"])
        XCTAssertEqual(obj["pinned"] as? Bool, true)
        let stash = try XCTUnwrap(obj["restartStash"] as? [String: Any])
        XCTAssertEqual(stash["texts"] as? [String], ["stashed plan"])
        XCTAssertEqual(stash["date"] as? String, "2026-06-19")
        let today = try XCTUnwrap(obj["today"] as? [String: Any])
        XCTAssertEqual(today["zzToday"] as? Int, 1)
        let it = try XCTUnwrap((today["items"] as? [[String: Any]])?.first)
        XCTAssertEqual(it["zzItem"] as? String, "ride")
        XCTAssertEqual(it["doneWord"] as? String, "Boom")     // Mac item field iOS doesn't model
        let hist = try XCTUnwrap((obj["history"] as? [[String: Any]])?.first)
        XCTAssertEqual(hist["zzHist"] as? Int, 9)
        let def = try XCTUnwrap((obj["deferred"] as? [[String: Any]])?.first)
        XCTAssertEqual(def["zzDef"] as? Int, 7)
        let settings = try XCTUnwrap(obj["settings"] as? [String: Any])
        XCTAssertEqual(settings["historyDays"] as? Int, 14)
    }

    // MARK: - contentKey exclusions: savedAt / deferred v / extras must NOT churn the key.
    func testContentKeyExcludesVolatileFields() {
        let base = snap(today: TodayState(date: "d", items: [item("a","alpha")]),
                        deferred: [DeferredTask(id: "d1", text: "p", wake: "", v: 1)],
                        settings: .default, savedAt: 1000)
        var b2 = base; b2.savedAt = 999_999                                  // savedAt excluded
        XCTAssertEqual(BuddySync.contentKey(base), BuddySync.contentKey(b2))
        var b3 = base; b3.deferred[0].v = 5                                  // deferred v excluded
        XCTAssertEqual(BuddySync.contentKey(base), BuddySync.contentKey(b3))
        var b4 = base; b4.extras = ["pinned": .bool(true), "restartStash": .object(["texts": .array([.string("x")])])]
        XCTAssertEqual(BuddySync.contentKey(base), BuddySync.contentKey(b4)) // extras (pinned/restartStash) excluded
        var b5 = base
        b5.settings = BuddySettings(celebrate: 100, historyDays: 3, reserveSpace: false)
        XCTAssertEqual(BuddySync.contentKey(base), BuddySync.contentKey(b5)) // historyDays excluded
        var b6 = base; b6.today?.items[0].text = "beta"                      // real change IS detected
        XCTAssertNotEqual(BuddySync.contentKey(base), BuddySync.contentKey(b6))
        var b7 = base; b7.today?.items[0].extras = ["zz": .int(1)]           // item extras excluded
        XCTAssertEqual(BuddySync.contentKey(base), BuddySync.contentKey(b7))
    }

    // MARK: - contentKey BYTE PARITY with the Mac. Expected strings were computed by
    // running the Mac's own canonicalJSON/_ckItem/_ckDef/blobContentKey (dist/index.html)
    // in node over this exact fixture. If Swift ever drifts a byte, the two platforms
    // stop agreeing on "who's newer" ties and can diverge — this test pins it.
    func testContentKeyByteParityWithMac() {
        let s = snap(
            today: TodayState(date: "2026-06-21", items: [
                item("m2", "done ✓", .done, 2, Date(timeIntervalSince1970: 1_750_000_005)),
                item("m1", "alpha \"quoted\"\nline", .neutral, 1),
            ], morningDone: true),
            history: [
                Day(date: "2026-06-19", weekday: "", items: [DayItem(id: "h-2026-06-19-0", text: "old", done: false)]),
                Day(date: "2026-06-20", weekday: "Friday", items: [DayItem(id: "h-2026-06-20-0", text: "yesterday", done: true)]),
            ],
            deferred: [
                DeferredTask(id: "d2", text: "later", wake: "2026-06-25", sent: true, sentTid: "m1", v: 3),
                DeferredTask(id: "d1", text: "plain", wake: "", v: 1),
            ],
            settings: BuddySettings(celebrate: 80, historyDays: 14, reserveSpace: false),
            tombstones: ["gone": 1_750_000_004],
            erasedAt: nil,
            savedAt: 1_750_000_123.456,
            extras: ["pinned": .bool(true), "restartStash": .object(["texts": .array([.string("x")]), "date": .string("2026-06-20")])]
        )
        let expected = #"{"d":[{"id":"d1","text":"plain","wake":""},{"id":"d2","sent":true,"sentTid":"m1","text":"later","wake":"2026-06-25"}],"e":null,"h":[{"date":"2026-06-20","items":[{"done":true,"id":"h-2026-06-20-0","text":"yesterday"}],"weekday":"Friday"},{"date":"2026-06-19","items":[{"done":false,"id":"h-2026-06-19-0","text":"old"}],"weekday":""}],"m":true,"s":{"celebrate":80,"reserveSpace":false},"t":[{"id":"m1","state":"neutral","text":"alpha \"quoted\"\nline","v":1},{"doneAt":1750000005000,"id":"m2","state":"done","text":"done ✓","v":2}],"td":"2026-06-21","tomb":{"gone":1750000004000}}"#
        XCTAssertEqual(BuddySync.contentKey(s), expected)

        // Minimal blob with NO settings → the Mac renders celebrate as null.
        let empty = snap(today: TodayState(date: "2026-06-21", items: []), settings: nil, savedAt: 0)
        XCTAssertEqual(BuddySync.contentKey(empty),
                       #"{"d":[],"e":null,"h":[],"m":false,"s":{"celebrate":null,"reserveSpace":false},"t":[],"td":"2026-06-21","tomb":{}}"#)
    }

    // MARK: - histId natural sort (h-<date>-<i>): numeric index order past 9; foreign ids last.
    func testHistIdNaturalSortInMergedRecord() {
        let x = Day(date: "2026-06-19", weekday: "Friday", items: [
            DayItem(id: "h-2026-06-19-10", text: "ten", done: false),
            DayItem(id: "zzz-foreign", text: "foreign", done: false),
        ])
        let y = Day(date: "2026-06-19", weekday: "Friday", items: [
            DayItem(id: "h-2026-06-19-2", text: "two", done: true),
        ])
        let m = BuddyMerge.mergeHistRecord(x, y)
        XCTAssertEqual(m.items.map { $0.id }, ["h-2026-06-19-2", "h-2026-06-19-10", "zzz-foreign"])
    }

    // MARK: - mergeHistRecord: done-wins + deterministic text winner + weekday min, symmetric.
    func testMergeHistRecordIsSymmetricOnTextConflict() {
        let x = Day(date: "2026-06-19", weekday: "Friday", items: [DayItem(id: "h-2026-06-19-0", text: "Alpha", done: false)])
        let y = Day(date: "2026-06-19", weekday: "", items: [DayItem(id: "h-2026-06-19-0", text: "Beta", done: true)])
        for m in [BuddyMerge.mergeHistRecord(x, y), BuddyMerge.mergeHistRecord(y, x)] {
            XCTAssertEqual(m.items.count, 1)
            XCTAssertEqual(m.items[0].text, "Alpha")   // smaller canonical projection wins
            XCTAssertEqual(m.items[0].done, true)      // done-wins
            XCTAssertEqual(m.weekday, "Friday")        // non-empty wins over empty
        }
    }

    // MARK: - wire codec: deferred `v` round-trips; a pre-v blob defaults to 1.
    func testDeferredVersionOnTheWire() throws {
        let s = snap(deferred: [DeferredTask(id: "d1", text: "p", wake: "", v: 4)], savedAt: 1000)
        let back = try JSONDecoder().decode(SyncWire.self, from: JSONEncoder().encode(SyncWire(s))).toSnapshot()
        XCTAssertEqual(back.deferred.first?.v, 4)

        let legacy = """
        { "version":1, "savedAt":0, "today":{"date":"d","morningDone":false,"items":[]},
          "history":[], "deferred":[{"id":"d1","text":"p","wake":""}], "tombstones":{}, "erasedAt":null }
        """
        let old = try JSONDecoder().decode(SyncWire.self, from: Data(legacy.utf8)).toSnapshot()
        XCTAssertEqual(old.deferred.first?.v, 1)
    }

    // MARK: - 22. Same-title deferred dedupe (mirrors Mac mergeTest 22): two devices
    // parking the same task mint two ids; the union collapses to ONE deterministic
    // winner. A reconciled orphan (dangling sentTid) joins the dedupe and can win on v.
    func testDeferredSameTitleDedupeIsDeterministicAndSymmetric() {
        let a = snap(deferred: [DeferredTask(id: "w1", text: "Warren Logo", wake: "", v: 1),
                                DeferredTask(id: "r1", text: "Richie Email", wake: "", v: 2)],
                     savedAt: 2000)
        let b = snap(deferred: [DeferredTask(id: "w2", text: "Warren Logo", wake: "", v: 2),
                                DeferredTask(id: "r2", text: "Richie Email", wake: "", v: 1),
                                DeferredTask(id: "s1", text: "Warren Logo", wake: "",
                                             sent: true, sentTid: "nope", v: 3)],
                     savedAt: 1000)
        let m1 = BuddyMerge.merge(a, b)!
        let m2 = BuddyMerge.merge(b, a)!
        XCTAssertEqual(m1.deferred.map(\.id).sorted(), m2.deferred.map(\.id).sorted())
        let plain = m1.deferred.filter { $0.sent != true }
        XCTAssertEqual(plain.map(\.text).sorted(), ["Richie Email", "Warren Logo"])
        // s1's sent flag reconciles away (dangling sentTid) → plain v3 wins the Warren slot.
        XCTAssertEqual(plain.first { $0.text == "Warren Logo" }?.v, 3)
        XCTAssertEqual(plain.first { $0.text == "Richie Email" }?.v, 2)
    }
}
