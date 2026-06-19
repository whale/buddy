import Foundation

// MARK: - Persisted settings
// Mirrors: state.settings in the Mac app.
// reserveSpace is Mac-only (pushes other windows) — included for blob parity but has no effect on iOS.
struct BuddySettings: Codable {
    var celebrate: Int        // 0–100: confetti intensity (0 = none, 100 = full burst)
    var historyDays: Int      // 0 (off) … 14: how many past days the history panel shows
    var reserveSpace: Bool    // Mac-only; ignored on iOS

    static let `default` = BuddySettings(celebrate: 100, historyDays: 7, reserveSpace: false)
}
