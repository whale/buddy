import XCTest
@testable import Buddy

// Slice 2 — persisted savedAt semantics (last USER mutation, never "now"), the
// editing guard, and the corrupt-store set-aside/backup recovery path.
final class StorePersistenceTests: XCTestCase {

    private func task(_ id: String, _ text: String) -> BuddyTask {
        BuddyTask(id: id, text: text, state: .neutral)
    }
    private func snap(_ items: [BuddyTask], savedAt: Double) -> SyncSnapshot {
        SyncSnapshot(today: TodayState(date: BuddyStore.localDate(), items: items, morningDone: true),
                     history: [], deferred: [], settings: .default,
                     tombstones: [:], erasedAt: nil, savedAt: savedAt)
    }

    // MARK: - savedAt = last user mutation

    // Adopting a merged snapshot takes the merged stamp — it must NOT claim "newer"
    // (each device stamping now-at-snapshot was the root of the always-newer jitter).
    func testAdoptDoesNotClaimNewer() {
        let store = BuddyStore()
        store.adopt(snap([task("A", "a")], savedAt: 1234))
        XCTAssertEqual(store.snapshot().savedAt, 1234)
        // …and a second snapshot a moment later still reports the SAME stamp.
        XCTAssertEqual(store.snapshot().savedAt, 1234)
    }

    // A genuine local mutation DOES stamp savedAt to now.
    func testLocalMutationStampsSavedAt() {
        let store = BuddyStore()
        store.adopt(snap([], savedAt: 1234))
        _ = store.addTask()
        let now = Date().timeIntervalSince1970
        XCTAssertEqual(store.snapshot().savedAt, now, accuracy: 5)
    }

    // MARK: - editing guard: adopt() defers while a row edit is in flight.

    func testAdoptIsDeferredWhileEditing() {
        let store = BuddyStore()
        store.adopt(snap([task("A", "mine")], savedAt: 1000))
        store.isEditing = true
        store.adopt(snap([task("B", "remote")], savedAt: 2000))
        XCTAssertEqual(store.today.items.map { $0.id }, ["A"])     // untouched mid-edit
        store.isEditing = false
        store.adopt(snap([task("B", "remote")], savedAt: 2000))
        XCTAssertEqual(store.today.items.map { $0.id }, ["B"])     // next pass lands
    }

    // MARK: - corrupt-store safety

    private func wipeStoreFiles() {
        let fm = FileManager.default
        for url in [BuddyStore.storeURL, BuddyStore.backupURL, BuddyStore.corruptURL] {
            try? fm.removeItem(at: url)
        }
    }

    // An unreadable primary is MOVED aside (kept for forensics), and the store boots
    // fresh instead of crashing — and the garbage can never be silently overwritten.
    func testCorruptPrimaryIsSetAsideAndBootsFresh() throws {
        wipeStoreFiles()
        let garbage = Data("{ not json ]]]".utf8)
        try garbage.write(to: BuddyStore.storeURL)

        let store = BuddyStore()

        XCTAssertTrue(store.today.items.isEmpty)                                  // fresh boot
        let kept = try Data(contentsOf: BuddyStore.corruptURL)
        XCTAssertEqual(kept, garbage)                                             // original preserved byte-for-byte
        wipeStoreFiles()
    }

    // With a valid backup present, a corrupt primary recovers from the backup.
    func testCorruptPrimaryRecoversFromBackup() throws {
        wipeStoreFiles()
        let today = BuddyStore.localDate()
        let backup = """
        { "version": 1, "savedAt": 4321,
          "today": { "date": "\(today)", "morningDone": true,
                     "items": [ { "id": "bk", "text": "from backup", "state": "neutral", "v": 2 } ] },
          "history": [], "deferred": [], "tombstones": {}, "erasedAt": null }
        """
        try Data(backup.utf8).write(to: BuddyStore.backupURL)
        try Data("garbage!!".utf8).write(to: BuddyStore.storeURL)

        let store = BuddyStore()

        XCTAssertEqual(store.today.items.map { $0.text }, ["from backup"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: BuddyStore.corruptURL.path))
        wipeStoreFiles()
    }

    // A healthy load refreshes the backup copy so the NEXT corruption is recoverable.
    func testSuccessfulLoadRefreshesBackup() throws {
        wipeStoreFiles()
        let today = BuddyStore.localDate()
        let good = """
        { "version": 1, "savedAt": 99,
          "today": { "date": "\(today)", "morningDone": true, "items": [] },
          "history": [], "deferred": [], "tombstones": {}, "erasedAt": null }
        """
        try Data(good.utf8).write(to: BuddyStore.storeURL)

        _ = BuddyStore()

        let bak = try Data(contentsOf: BuddyStore.backupURL)
        XCTAssertEqual(bak, Data(good.utf8))
        wipeStoreFiles()
    }
}
