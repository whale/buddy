import SwiftUI

// MARK: - Buddy card
// The Mac's `.bcard`: a rounded-24 panel with a layered macOS shadow (soft ramp,
// no hairline border). Suppressed at lvl2 (red-on-red would just muddy).
private struct BuddyCard: ViewModifier {
    let fill: Color
    let shadow: Bool

    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            // Three stacked shadows mirror the Mac's layered ramp:
            //   0 1 4 /.04 · 0 6 16 /.06 · 0 14 34 /.09  (blur ≈ 2·radius)
            .shadow(color: shadow ? .black.opacity(0.04) : .clear, radius: 2,  y: 1)
            .shadow(color: shadow ? .black.opacity(0.06) : .clear, radius: 8,  y: 6)
            .shadow(color: shadow ? .black.opacity(0.09) : .clear, radius: 17, y: 14)
    }
}

extension View {
    func buddyCard(fill: Color, shadow: Bool = true) -> some View {
        modifier(BuddyCard(fill: fill, shadow: shadow))
    }
}

// MARK: - Sheet chrome
// The Mac's Settings/History sheets use a fixed 68px header: a title (or segmented
// control) on the left, a round ✕ close on the right, then a hairline divider. This
// reproduces that so both sheets share the exact same top.
struct BuddySheetHeader<Leading: View>: View {
    let theme: EscalationTheme
    let onClose: () -> Void
    @ViewBuilder var leading: Leading

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(theme.chromeInk)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 28)
            .padding(.trailing, 16)
            .frame(height: 60)
            Rectangle().fill(theme.line).frame(height: 1)
        }
    }
}

extension EscalationTheme {
    // Settings/sheet title (Mac: black/80, white on red). Labels: black/60, white on red.
    var sheetTitle: Color { level == .lvl2 ? Color.white.opacity(0.92) : Color.black.opacity(0.8) }
    var sheetLabel: Color { level == .lvl2 ? Color.white.opacity(0.92) : Color.black.opacity(0.6) }
    var sheetFaint: Color { level == .lvl2 ? Color.white.opacity(0.5)  : Color.black.opacity(0.35) }
}

// MARK: - Chrome button
// A header glyph (pin / calendar / gear). 39pt round tap target, icon tinted by the
// escalation chrome-ink. SF Symbols stand in for the Mac's Lucide strokes.
struct ChromeButton: View {
    let systemName: String
    let size: CGFloat
    let ink: Color
    var selected: Bool = false
    var selBg: Color = .black
    var selInk: Color = .white
    let action: () -> Void

    init(_ systemName: String, size: CGFloat = 17, ink: Color,
         selected: Bool = false, selBg: Color = .black, selInk: Color = .white,
         action: @escaping () -> Void) {
        self.systemName = systemName
        self.size = size
        self.ink = ink
        self.selected = selected
        self.selBg = selBg
        self.selInk = selInk
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(selected ? selInk : ink)
                .frame(width: 39, height: 39)
                .background(selected ? selBg : .clear, in: Circle())   // filled circle when active (Mac chrome-btn.sel)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
