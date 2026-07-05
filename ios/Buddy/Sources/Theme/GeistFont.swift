import SwiftUI

// MARK: - Geist typeface
// Buddy's Mac app is set in Geist (SIL OFL). These helpers map SwiftUI weights to
// the bundled static OTFs (PostScript names Geist-Regular/Medium/SemiBold/Bold) so
// the iPhone shares the exact same type language.
//
// We use `fixedSize:` (NOT `size:`) so the pixel sizes match the Mac's fixed layout
// exactly rather than scaling with Dynamic Type — Buddy is a compact, tuned surface,
// not flowing body text. If a Dynamic-Type mode is wanted later, switch to `size:`.
extension Font {
    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(psName(for: weight), fixedSize: size)
    }

    private static func psName(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black:   return "Geist-Bold"
        case .semibold:               return "Geist-SemiBold"
        case .medium:                 return "Geist-Medium"
        default:                      return "Geist-Regular"
        }
    }
}

// MARK: - Font load guard (DEBUG)
// If a PostScript name is wrong, SwiftUI silently falls back to the system font — a
// parity trap that's invisible in code review. This asserts the four faces registered.
#if DEBUG
enum GeistFontCheck {
    static func run() {
        let want = ["Geist-Regular", "Geist-Medium", "Geist-SemiBold", "Geist-Bold"]
        for name in want {
            if UIFont(name: name, size: 12) == nil {
                print("⚠️ [Geist] MISSING FONT: \(name) — text will fall back to system.")
            }
        }
        let geist = UIFont.familyNames.filter { $0.lowercased().contains("geist") }
        print("✅ [Geist] families present: \(geist)")
    }
}
#endif
