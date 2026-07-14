import XCTest
import CryptoKit
@testable import Buddy

// E2E blob crypto — MUST stay byte-compatible with dist/index.html (syncTest case 12).
// The pinned vector: syncKey = 43 'A's (32 zero bytes) → HKDF-SHA256(empty salt,
// info "buddy-blob-v1") → AES-256-GCM with a zero IV over {"probe":1}.
final class BlobCryptoTests: XCTestCase {
    let zeroSyncKey = String(repeating: "A", count: 43)

    func testDerivedKeyMatchesSharedVector() {
        let key = BlobCrypto.deriveKey(syncKey: zeroSyncKey)
        XCTAssertNotNil(key)
        let hex = key!.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
        // Same value the Mac derives (computed with WebCrypto, pinned on both platforms).
        XCTAssertEqual(hex, "0692ba686f1baddc21ffc688c1d14d4ab72f56b311968b1efbce4b1418e01ca2")
    }

    func testCiphertextMatchesSharedVector() throws {
        let key = BlobCrypto.deriveKey(syncKey: zeroSyncKey)!
        let env = try BlobCrypto.encrypt(Data("{\"probe\":1}".utf8), key: key,
                                         nonce: Data(repeating: 0, count: 12))
        XCTAssertEqual(env["ct"] as? String, "dwuU613APPxtAVftrUOhEcoNMm60PbSF04gQ",
                       "ciphertext+tag must match the Mac's WebCrypto output byte-for-byte")
        XCTAssertEqual(env["iv"] as? String, "AAAAAAAAAAAAAAAA")
        XCTAssertEqual(env["enc"] as? Int, 1)
    }

    func testRoundTrip() throws {
        let key = BlobCrypto.deriveKey(syncKey: SyncIdentity.generateKey())!
        let pt = Data("{\"today\":{\"date\":\"2026-07-14\",\"items\":[]}}".utf8)
        let env = try BlobCrypto.encrypt(pt, key: key)
        XCTAssertTrue(BlobCrypto.isEnvelope(env))
        XCTAssertEqual(try BlobCrypto.decrypt(env, key: key), pt)
    }

    func testTamperedCiphertextThrows() throws {
        let key = BlobCrypto.deriveKey(syncKey: zeroSyncKey)!
        var env = try BlobCrypto.encrypt(Data("{\"probe\":1}".utf8), key: key)
        let ct = env["ct"] as! String
        env["ct"] = String(ct.dropLast()) + (ct.hasSuffix("A") ? "B" : "A")
        XCTAssertThrowsError(try BlobCrypto.decrypt(env, key: key),
                             "a flipped byte must fail the GCM tag, never yield garbage")
    }

    func testWrongKeyThrows() throws {
        let k1 = BlobCrypto.deriveKey(syncKey: zeroSyncKey)!
        let k2 = BlobCrypto.deriveKey(syncKey: SyncIdentity.generateKey())!
        let env = try BlobCrypto.encrypt(Data("{\"probe\":1}".utf8), key: k1)
        XCTAssertThrowsError(try BlobCrypto.decrypt(env, key: k2))
    }

    func testEnvelopeDetection() {
        XCTAssertTrue(BlobCrypto.isEnvelope(["enc": 1, "iv": "x", "ct": "y"]))
        XCTAssertFalse(BlobCrypto.isEnvelope(["today": ["items": []]]))   // legacy plaintext blob
        XCTAssertFalse(BlobCrypto.isEnvelope(nil))
        XCTAssertFalse(BlobCrypto.isEnvelope("string"))
    }

    func testMalformedSyncKeyYieldsNoKey() {
        XCTAssertNil(BlobCrypto.deriveKey(syncKey: ""))
        XCTAssertNil(BlobCrypto.deriveKey(syncKey: "short"))
    }

    // A legacy PLAINTEXT remote row with content EQUAL to local must still be pushed
    // once (the encrypt upgrade), then never again — mirrors the Mac's syncTest 12d.
    func testPlainRemoteForcesOneUpgradePush() async throws {
        let snap = SyncSnapshot(today: TodayState(date: "2026-07-14", items: [], morningDone: false),
                                history: [], deferred: [], settings: nil,
                                tombstones: [:], erasedAt: nil, savedAt: 0)
        let inner = InMemoryCASStore(seed: (key: "k", blob: snap, version: 3))
        let plainOnce = PlainFlaggingStore(inner: inner)   // reports plain:true like a legacy row
        let res = try await BuddySync.syncOnce(store: plainOnce, key: "k", local: snap)
        XCTAssertTrue(res.ok)
        XCTAssertTrue(res.pushed, "equal-content plaintext row must be re-pushed (encrypt upgrade)")
        let v = await inner.currentVersion("k")
        XCTAssertEqual(v, 4)
    }
}

/// Test double: wraps the in-memory store and flags pulls as plaintext — the situation
/// a real client sees the first time it syncs against a pre-E2E row.
private struct PlainFlaggingStore: CASStore {
    let inner: InMemoryCASStore
    func pull(_ key: String) async throws -> PullResult {
        let r = await inner.pull(key)
        return PullResult(blob: r.blob, version: r.version, plain: r.blob != nil)
    }
    func push(_ key: String, blob: SyncSnapshot, expected: Int) async throws -> PushResult {
        await inner.push(key, blob: blob, expected: expected)
    }
}
