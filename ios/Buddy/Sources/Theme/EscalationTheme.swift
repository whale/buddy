import SwiftUI

// MARK: - Escalation levels
// Mirrors the web app's .lvl0 / .lvl1 / .lvl2 CSS classes.
// Source: dist/index.html — the #drawer.lvlN variable blocks.
enum EscalationLevel: Int {
    case lvl0 = 0   // ≤4 active — normal (white cards, black text)
    case lvl1 = 1   // exactly 5 active — warning (white cards, RED text)
    case lvl2 = 2   // ≥6 active — alarm (RED cards, white text)

    static func from(activeCount: Int) -> EscalationLevel {
        switch activeCount {
        case ..<5: return .lvl0
        case 5:    return .lvl1
        default:   return .lvl2
        }
    }
}

// MARK: - Escalation theme
// All colours derived from the shared token contract so they stay in sync:
//   design/escalation-tokens.json (pinned by EscalationTokenParityTests).
// The red value (#e5484d) matches `--red` in the web app root.
// THE PATTERN (2026-07-10): EVERY text/element follows lvl0 black-on-white,
// lvl1 red-on-white, lvl2 white-on-red. No carve-outs — done rows, day
// headers, glyphs and settings controls all follow.
struct EscalationTheme {
    let level: EscalationLevel

    // Card / view background
    var cardBackground: Color {
        switch level {
        case .lvl0, .lvl1: return .white
        case .lvl2:        return Color(hex: "#e5484d")
        }
    }

    // Primary text — task titles, labels, done words. Follows THE PATTERN:
    // black → red → white (done rows included; the old "done stays neutral
    // at lvl1" carve-out was removed 2026-07-10).
    var ink: Color {
        switch level {
        case .lvl0: return .black
        case .lvl1: return Color(hex: "#e5484d")
        case .lvl2: return .white
        }
    }

    // Secondary text — done/dim rows, timestamps. Same pattern at 45/65/60%.
    var inkDim: Color {
        switch level {
        case .lvl0: return Color.black.opacity(0.45)
        case .lvl1: return Color(hex: "#e5484d").opacity(0.65)
        case .lvl2: return Color.white.opacity(0.6)
        }
    }

    // Small functional glyphs — swipe-action icons, row icons.
    // Grey at rest, red at lvl1, near-white on the red card.
    var glyph: Color {
        switch level {
        case .lvl0: return Color(hex: "#8c8c8c")
        case .lvl1: return Color(hex: "#e5484d")
        case .lvl2: return Color.white.opacity(0.92)
        }
    }

    // Active task number/text escalation colour
    // lvl0 = black, lvl1 = red (the warning signal), lvl2 = white
    var escalationText: Color {
        switch level {
        case .lvl0: return .black
        case .lvl1: return Color(hex: "#e5484d")
        case .lvl2: return .white
        }
    }

    // Divider / border lines
    var line: Color {
        switch level {
        case .lvl0, .lvl1: return Color(hex: "#d9d9d9")
        case .lvl2:        return Color.white.opacity(0.3)
        }
    }

    // Header chrome glyphs (pin / calendar / gear). Mac --chrome-ink:
    //   lvl0 rgba(0,0,0,.45) · lvl1 red · lvl2 #fff
    var chromeInk: Color {
        switch level {
        case .lvl0: return Color.black.opacity(0.45)
        case .lvl1: return Color(hex: "#e5484d")
        case .lvl2: return .white
        }
    }

    // Muted chrome TEXT — the "Buddy" title + the month line. Mac: text-black/60 with
    // the `.chrome` class, so it reddens at lvl1 and goes white at lvl2.
    var chromeMuted: Color {
        switch level {
        case .lvl0: return Color.black.opacity(0.6)
        case .lvl1: return Color(hex: "#e5484d")
        case .lvl2: return .white
        }
    }

    // "Add +" placeholder text. Mac --addtxt: lvl0/1 rgba(0,0,0,.20) · lvl2 rgba(255,255,255,.60)
    var addInk: Color {
        switch level {
        case .lvl0, .lvl1: return Color.black.opacity(0.20)
        case .lvl2:        return Color.white.opacity(0.60)
        }
    }

    // The backdrop the floating cards sit on — ALWAYS the neutral "desktop", at every
    // level. At lvl2 only the CARDS turn red (like the Mac, where red panels sit on the
    // unchanged desktop); the backdrop staying neutral keeps the card edges + dividers
    // reading. (Was red at lvl2, which merged everything into one field — wrong.)
    var screenBackground: Color { Color(hex: "#ececee") }

    // macOS-style layered panel shadow (.bcard). Suppressed at lvl2 (red on red).
    var cardShadow: Color { level == .lvl2 ? .clear : Color.black.opacity(0.10) }

    // Selected chrome glyph (the filled circle behind the active header icon). Mac --sel-bg
    // / --sel-ink: lvl0 black-on-white · lvl1 red-on-white · lvl2 white-on-red.
    var selBg: Color {
        switch level {
        case .lvl0: return .black
        case .lvl1: return Color(hex: "#e5484d")
        case .lvl2: return .white
        }
    }
    var selInk: Color { level == .lvl2 ? Color(hex: "#e5484d") : .white }

    // Focused ("now") row fill. Mirrors the Mac:
    //   .row-focused { background:#f4f4f4 }  (lvl0/1)
    //   .lvl2 .row-focused { red + 15% black overlay } → ≈ #c33d41
    var focusFill: Color {
        switch level {
        case .lvl0, .lvl1: return Color(hex: "#f4f4f4")
        case .lvl2:        return Color(hex: "#c33d41")
        }
    }

    // Swipe-action tray behind a row. Neutral grey at lvl0/1; on the red card
    // it's the card red darkened ~18% (the Mac's tray-on-red idiom) so the
    // tray still reads as "behind" while the glyphs stay legible.
    var swipeActionBg: Color {
        switch level {
        case .lvl0, .lvl1: return Color(hex: "#ececec")
        case .lvl2:        return Color(hex: "#bc3b3f")   // #e5484d + rgba(0,0,0,0.18) overlay
        }
    }
    var swipeDivider: Color {
        switch level {
        case .lvl0, .lvl1: return Color(hex: "#c9c9c9")
        case .lvl2:        return Color.white.opacity(0.3)
        }
    }

    // Segmented control (Mac .seg-sel): the selected pill stays WHITE at every
    // level; its label is black → red → red. The track is faint black on light,
    // faint white on the red card.
    var segSelInk: Color { level == .lvl0 ? .black : Color(hex: "#e5484d") }
    var segTrack: Color { level == .lvl2 ? Color.white.opacity(0.20) : Color.black.opacity(0.05) }

    // Settings slider (Mac .buddy-range): solid thumb black → red → white,
    // thin track at black-15% → red-25% → white-30%.
    var sliderThumb: Color {
        switch level {
        case .lvl0: return .black
        case .lvl1: return Color(hex: "#e5484d")
        case .lvl2: return .white
        }
    }
    var sliderTrack: Color {
        switch level {
        case .lvl0: return Color.black.opacity(0.15)
        case .lvl1: return Color(hex: "#e5484d").opacity(0.25)
        case .lvl2: return Color.white.opacity(0.30)
        }
    }

    // Error text (Mac #syncError): token red on light surfaces; red-on-red is
    // invisible at lvl2 → white there.
    var errorText: Color { level == .lvl2 ? .white : Color(hex: "#e5484d") }

    // Convenience factory
    static func from(activeCount: Int) -> EscalationTheme {
        EscalationTheme(level: .from(activeCount: activeCount))
    }
}

// MARK: - Hex color initializer
// Used throughout the app to match web-app hex tokens exactly.
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (r, g, b, a) = (int >> 16, (int >> 8) & 0xFF, int & 0xFF, 0xFF)
        case 8:
            (r, g, b, a) = (int >> 24, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 0xFF)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
