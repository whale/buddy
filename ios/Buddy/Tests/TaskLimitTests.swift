import XCTest
@testable import Buddy

final class TaskLimitTests: XCTestCase {
    private func snapshot(_ items: [BuddyTask], limit: Int? = nil, date: String = "2026-09-16") -> SyncSnapshot {
        var s = SyncSnapshot(today: TodayState(date: date, items: items, morningDone: true), history: [], deferred: [], settings: .default, tombstones: [:], erasedAt: nil, savedAt: 1000)
        if let limit { s.extras["taskLimit"] = TaskLimit(value: limit, v: 2, writer: "mac").json }
        return s
    }
    private func item(_ id: String, _ text: String, _ v: Int = 1, done: Bool = false) -> BuddyTask {
        BuddyTask(id: id, text: text, state: done ? .done : .neutral, doneAt: done ? Date(timeIntervalSince1970: 1000) : nil, v: v)
    }
    func testAllLimitMath() {
        for limit in 3...6 {
            for n in 0...8 {
                let expected: EscalationLevel = n >= limit ? .lvl2 : n == limit - 1 ? .lvl1 : .lvl0
                XCTAssertEqual(EscalationLevel.from(activeCount: n, limit: limit), expected)
                let result = BuddyMerge.clampActive((0..<n).map { item("x\($0)", "Task \($0)") }, limit: limit)
                XCTAssertEqual(result.kept.count, min(n, limit))
                XCTAssertEqual(result.overflow.count, max(0, n - limit))
            }
        }
    }
    func testLimitSurvivesNewerUnrelatedLegacySave() throws {
        let items = (0..<6).map { item("x\($0)", "Task \($0)") }
        let a = snapshot(items, limit: 3)
        var b = snapshot(items); b.savedAt = 2000
        let m = try XCTUnwrap(BuddyMerge.merge(a,b))
        XCTAssertEqual(TaskLimit.normalized(m.extras["taskLimit"]).value, 3)
        XCTAssertEqual(m.today?.items.count, 3)
        XCTAssertEqual(m.deferred.count, 3)
        XCTAssertEqual(BuddySync.contentKey(m), BuddySync.contentKey(BuddyMerge.merge(b,a)))
        XCTAssertNotEqual(BuddySync.contentKey(a), BuddySync.contentKey(snapshot(items)))
    }
    func testParkedTaskPreservesOfflineEditAndCompletionAcrossRollover() throws {
        for oldDate in ["2026-09-16", "2026-09-15"] {
            for done in [false,true] {
                var a = snapshot([], limit: 3)
                a.deferred = [DeferredTask(id: "x", text: "Old title", wake: "", v: 1)]
                let b = snapshot([item("x", "Updated title", 2, done: done)], date: oldDate)
                let m = try XCTUnwrap(BuddyMerge.merge(a,b))
                if done {
                    XCTAssertFalse(m.deferred.contains { $0.id == "x" })
                    XCTAssertTrue(m.history.contains { $0.items.contains { $0.id == "x" && $0.text == "Updated title" && $0.done } })
                } else {
                    XCTAssertEqual(m.deferred.first { $0.id == "x" }?.text, "Updated title")
                    XCTAssertEqual(m.deferred.first { $0.id == "x" }?.v, 2)
                }
                XCTAssertEqual(BuddySync.contentKey(m), BuddySync.contentKey(BuddyMerge.merge(b,a)))
                XCTAssertEqual(BuddySync.contentKey(m), BuddySync.contentKey(BuddyMerge.merge(m,b)))
                XCTAssertEqual(BuddySync.contentKey(m), BuddySync.contentKey(BuddyMerge.merge(m,a)))
            }
        }
    }
    func testConfirmedSelectionIsNotOverparkedByStalePeer() throws {
        let all = (0..<6).map { item("x\($0)", "Task \($0)") }
        var chosen = snapshot(Array(all.suffix(3)), limit: 3)
        chosen.deferred = all.prefix(3).map { DeferredTask(id:$0.id,text:$0.text,wake:"",v:$0.v) }
        let m = try XCTUnwrap(BuddyMerge.merge(chosen,snapshot(all)))
        XCTAssertEqual(Set(m.today?.items.map { $0.id } ?? []), Set(["x3","x4","x5"]))
        XCTAssertEqual(m.deferred.count, 3)
    }
    func testNormalizationAndRevisionTieBreak() {
        XCTAssertEqual(TaskLimit.normalized(nil).value, 6)
        XCTAssertEqual(TaskLimit.normalized(.object(["value":.int(2),"v":.int(1),"writer":.string("mac")])).value, 3)
        XCTAssertEqual(TaskLimit.normalized(.object(["value":.number(3.5),"v":.int(1),"writer":.string("mac")])).value, 6)
        let a = TaskLimit(value:3,v:4,writer:"a").json, b = TaskLimit(value:5,v:4,writer:"b").json
        XCTAssertEqual(TaskLimit.pick(a,b),TaskLimit.pick(b,a))
        XCTAssertEqual(TaskLimit.pick(a,b).value,5)
    }
    func testActualLegacyWireEncoderPreservesLimitThroughSettingsEdit() throws {
        let original = snapshot([], limit: 3)
        let encoded = try JSONEncoder().encode(SyncWire(original))
        var old = try JSONDecoder().decode(LegacySyncWire.self, from: encoded)
        old.settings?.celebrate = 50
        old.savedAt = 9_999_999
        let returned = try JSONDecoder().decode(SyncWire.self, from: JSONEncoder().encode(old)).toSnapshot()
        XCTAssertEqual(TaskLimit.normalized(returned.extras["taskLimit"]).value, 3)
        XCTAssertEqual(TaskLimit.normalized(returned.extras["taskLimit"]).v, 2)
    }

    func testStoreOperationsRespectEveryLimitAndPreserveOverflow() {
        for limit in 3...6 {
            let s = BuddyStore()
            s.extras["taskLimit"] = TaskLimit(value:limit,v:1,writer:"test").json
            s.today = TodayState(date:BuddyStore.localDate(),items:(0..<limit).map { item("x\($0)","Task \($0)") },morningDone:true)
            s.deferred = [DeferredTask(id:"future",text:"Parked",wake:"")]
            XCTAssertNil(s.addTask())
            s.restoreHistoryTask(text:"History task")
            s.wakeDeferredTask(id:"future")
            XCTAssertEqual(s.activeCount,limit)
            XCTAssertNil(s.deferred.first?.sent)
            XCTAssertTrue(s.complete(s.today.items[0]))
            XCTAssertEqual(s.freeSlots,1)
            s.restoreTask(id:"x0")
            XCTAssertEqual(s.activeCount,limit)
            XCTAssertTrue(s.complete(s.today.items[0]))
            XCTAssertNotNil(s.addTask())
            XCTAssertEqual(s.freeSlots,0) // a live blank draft owns its slot
            s.restoreTask(id:"x0")
            XCTAssertTrue(s.today.items.first { $0.id == "x0" }!.isDone)

            s.today = TodayState(date:"2020-01-01",items:(0..<6).map { item("r\($0)","Rollover \($0)") },morningDone:true)
            s.deferred = [];s.history = [];s.tombstones = [:];s.doneTombs = [:]
            XCTAssertTrue(s.performRolloverIfNeeded())
            XCTAssertEqual(s.activeCount,limit)
            XCTAssertEqual(s.deferred.count,6-limit)
            XCTAssertEqual(Set(s.today.items.map { $0.id } + s.deferred.map { $0.id }).count,6)
        }
    }

    func testLimitCannotChangeUntilTasksFitAndNeverMovesThem() {
        let s = BuddyStore()
        s.extras.removeValue(forKey:"taskLimit")
        s.today = TodayState(date:BuddyStore.localDate(),items:(0..<5).map { item("x\($0)","Task \($0)") },morningDone:true)
        s.deferred = []
        for limit in [3,4] {
            XCTAssertFalse(s.changeTaskLimit(limit,expectedSignature:s.activeSignature))
            XCTAssertEqual(s.taskLimit,6)
            XCTAssertEqual(s.activeCount,5)
            XCTAssertTrue(s.deferred.isEmpty)
        }
        let stale = s.activeSignature
        _ = s.complete(s.today.items[3]); _ = s.complete(s.today.items[4])
        XCTAssertFalse(s.changeTaskLimit(3,expectedSignature:stale))
        XCTAssertTrue(s.changeTaskLimit(3,expectedSignature:s.activeSignature))
        XCTAssertEqual(s.today.items.count,5)
        XCTAssertEqual(s.activeCount,3)
        XCTAssertTrue(s.deferred.isEmpty)
    }
}
