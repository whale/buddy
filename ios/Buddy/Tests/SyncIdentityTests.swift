import XCTest
@testable import Buddy

// QR-pairing identity. The owner_id vector is shared with the Mac's syncTest() —
// asserting the same hex on both sides proves JS and Swift derive the SAME owner_id
// from the same key, so a Mac-generated key works when scanned on the phone.
final class SyncIdentityTests: XCTestCase {

    func testOwnerIdMatchesCrossPlatformVector() {
        XCTAssertEqual(SyncIdentity.ownerId(for: "buddy-test-key"),
                       "9a39afad46d5205bc0d6abb9be6dd625649a796e09519cee438ba56b5899d79a")
    }

    func testOwnerIdIsDeterministicAndDistinct() {
        XCTAssertEqual(SyncIdentity.ownerId(for: "abc"), SyncIdentity.ownerId(for: "abc"))
        XCTAssertNotEqual(SyncIdentity.ownerId(for: "abc"), SyncIdentity.ownerId(for: "abd"))
    }

    func testGeneratedKeyIs256BitBase64URL() {
        let k = SyncIdentity.generateKey()
        XCTAssertEqual(k.count, 43)                                   // 32 bytes, base64url, unpadded
        XCTAssertNil(k.rangeOfCharacter(from: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_").inverted))
        XCTAssertNotEqual(k, SyncIdentity.generateKey())             // not constant
    }

    func testPairingPayloadRoundTrips() {
        let key = SyncIdentity.generateKey()
        let parsed = SyncIdentity.parse(SyncIdentity.payload(
            backendUrl: "https://x.supabase.co", anonKey: "anon-abc", syncKey: key))
        XCTAssertEqual(parsed?.syncKey, key)
        XCTAssertEqual(parsed?.backendUrl, "https://x.supabase.co")
        XCTAssertEqual(parsed?.anonKey, "anon-abc")
    }

    func testPairingPayloadRejectsGarbage() {
        XCTAssertNil(SyncIdentity.parse("not json"))
        XCTAssertNil(SyncIdentity.parse("{}"))
        XCTAssertNil(SyncIdentity.parse(#"{"backendUrl":"x","syncKey":"y"}"#))   // missing anonKey
        XCTAssertNil(SyncIdentity.parse(#"{"backendUrl":"x","anonKey":"a"}"#))   // missing syncKey
    }
}
