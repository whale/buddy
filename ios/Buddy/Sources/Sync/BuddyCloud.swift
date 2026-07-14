import Foundation

// MARK: - BuddyCloud — the hosted backend (iOS mirror of dist/config.js).
//
// OPEN-SOURCE DEFAULT: nil — no hosted backend exists in a clone of this repo; the
// Settings UI shows the self-host fields and only v1 (full) pairing QRs parse.
//
// HOSTED BUILDS: fastlane/CI overwrite this file with the real url + publishable key
// just before building, and never commit it. Those values are IDENTIFIERS, not
// secrets (Supabase documents publishable keys as safe to ship in clients); all
// enforcement is server-side. The v2 pairing QR carries only the syncKey and the
// phone resolves the backend from here — which is what keeps the hosted key
// rotatable without re-pairing every phone.
enum BuddyCloud {
    static let url: String? = nil
    static let anon: String? = nil

    static var present: Bool {
        !(url ?? "").isEmpty && !(anon ?? "").isEmpty
    }
}
