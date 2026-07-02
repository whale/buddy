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
// All colours derived from the web CSS variables so they stay in sync:
//   --card, --ink, --ink-dim in lvl0/1/2.
// The red value (#e5484d) matches `--red` in the web app root.
struct EscalationTheme {
    let level: EscalationLevel

    // Card / view background
    var cardBackground: Color {
        switch level {
        case .lvl0, .lvl1: return .white
        case .lvl2:        return Color(hex: "#e5484d")
        }
    }

    // Primary text — task titles, labels
    var ink: Color {
        switch level {
        case .lvl0, .lvl1: return .black
        case .lvl2:        return .white
        }
    }

    // Secondary text — done/dim rows, timestamps
    var inkDim: Color {
        switch level {
        case .lvl0, .lvl1: return Color.black.opacity(0.45)
        case .lvl2:        return Color.white.opacity(0.6)
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

    // The backdrop the floating cards sit on. lvl0/1 a light neutral so white cards
    // read as elevated (the Mac's desktop); lvl2 the whole screen goes red so it reads
    // as "the whole drawer turned red" (RULE 1) with the cards melting into it.
    var screenBackground: Color {
        switch level {
        case .lvl0, .lvl1: return Color(hex: "#ececee")
        case .lvl2:        return Color(hex: "#e5484d")
        }
    }

    // macOS-style layered panel shadow (.bcard). Suppressed at lvl2 (red on red).
    var cardShadow: Color { level == .lvl2 ? .clear : Color.black.opacity(0.10) }

    // Focused ("now") row fill. Mirrors the Mac:
    //   .row-focused { background:#f4f4f4 }  (lvl0/1)
    //   .lvl2 .row-focused { red + 15% black overlay } → ≈ #c33d41
    var focusFill: Color {
        switch level {
        case .lvl0, .lvl1: return Color(hex: "#f4f4f4")
        case .lvl2:        return Color(hex: "#c33d41")
        }
    }

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
