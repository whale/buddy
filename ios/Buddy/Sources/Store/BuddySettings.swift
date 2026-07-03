import Foundation

// MARK: - Persisted settings
// Mirrors: state.settings in the Mac app.
// reserveSpace is Mac-only (pushes other windows) — included for blob parity but has no effect on iOS.
struct BuddySettings: Codable {
    var celebrate: Int        // 0–100: confetti intensity (0 = none, 100 = full burst)
    var historyDays: Int      // 0 (off) … 14: how many past days the history panel shows
    var reserveSpace: Bool    // Mac-only; ignored on iOS

    static let `default` = BuddySettings(celebrate: 100, historyDays: 7, reserveSpace: false)

    init(celebrate: Int, historyDays: Int, reserveSpace: Bool) {
        self.celebrate = celebrate; self.historyDays = historyDays; self.reserveSpace = reserveSpace
    }

    // Tolerant decode: the Mac's serialize() emits only { celebrate, reserveSpace } — no
    // historyDays. A synthesized decoder would throw keyNotFound("historyDays") on EVERY Mac
    // blob and silently kill Mac→iOS sync. Default any missing field so cross-device blobs decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        celebrate    = try c.decodeIfPresent(Int.self,  forKey: .celebrate)    ?? Self.default.celebrate
        historyDays  = try c.decodeIfPresent(Int.self,  forKey: .historyDays)  ?? Self.default.historyDays
        reserveSpace = try c.decodeIfPresent(Bool.self, forKey: .reserveSpace) ?? Self.default.reserveSpace
    }
}
