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
            .frame(height: 68)   // matches the Mac sheet header h-[68px]
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

// MARK: - Swipeable row
// The Mac reveals row actions on hover; the iPhone has no hover, so we use swipe (the
// user's pick). Native `.swipeActions` only works inside a List — which can't do the
// equal-height flex rows — so this is a custom swipe that preserves the layout.
//   swipe RIGHT → Complete (leading) · swipe LEFT → Sleep · Delete (trailing) · tap → onTap (edit)
struct SwipeableRow<Content: View>: View {
    var cardFill: Color                 // opaque row bg so the actions hide when closed
    var onComplete: (() -> Void)? = nil
    var onSleep: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0        // snapped rest offset
    @GestureState private var drag: CGFloat = 0   // live drag delta
    private let actionW: CGFloat = 76

    private var trailing: [(String, Color, () -> Void)] {
        var a: [(String, Color, () -> Void)] = []
        if let onSleep  { a.append(("moon.zzz.fill", Color(hex: "#6b6b6b"), onSleep)) }
        if let onDelete { a.append(("trash.fill",     Color(hex: "#c62828"), onDelete)) }
        return a
    }
    private var trailingW: CGFloat { CGFloat(trailing.count) * actionW }
    private var leadingW: CGFloat { onComplete != nil ? actionW : 0 }
    private var visual: CGFloat { min(leadingW, max(-trailingW, offset + drag)) }

    var body: some View {
        ZStack {
            // Action layer (behind the content)
            HStack(spacing: 0) {
                if let onComplete {
                    actionButton("checkmark", Color(hex: "#30a46c")) { run(onComplete) }
                        .frame(width: actionW)
                }
                Spacer(minLength: 0)
                ForEach(Array(trailing.enumerated()), id: \.offset) { _, a in
                    actionButton(a.0, a.1) { run(a.2) }.frame(width: actionW)
                }
            }
            // Content on top, offset by the swipe; opaque so it covers the actions at rest.
            content()
                .background(cardFill)
                .offset(x: visual)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 14)
                        .updating($drag) { v, state, _ in
                            // horizontal intent only — ignore mostly-vertical drags
                            if abs(v.translation.width) > abs(v.translation.height) { state = v.translation.width }
                        }
                        .onEnded { v in
                            let o = offset + v.translation.width
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                if o < -trailingW * 0.5 { offset = -trailingW }
                                else if leadingW > 0 && o > leadingW * 0.5 { offset = leadingW }
                                else { offset = 0 }
                            }
                        }
                )
                .onTapGesture {
                    if offset != 0 { withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { offset = 0 } }
                    else { onTap?() }
                }
        }
        .clipped()
        #if DEBUG
        .onAppear {   // screenshot harness: -uiSwipeOpen 1 reveals the trailing actions
            if UserDefaults.standard.bool(forKey: "uiSwipeOpen") { offset = -trailingW }
        }
        #endif
    }

    private func actionButton(_ icon: String, _ bg: Color, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            bg.overlay(Image(systemName: icon).font(.system(size: 18)).foregroundStyle(.white))
        }
        .buttonStyle(.plain)
        .frame(maxHeight: .infinity)
    }

    private func run(_ a: @escaping () -> Void) {
        a()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { offset = 0 }
    }
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
                .font(.system(size: size, weight: .light))   // ≈ the Mac's Lucide 1.8 stroke (SF .regular reads heavier)
                .foregroundStyle(selected ? selInk : ink)
                .frame(width: 39, height: 39)
                .background(selected ? selBg : .clear, in: Circle())   // filled circle when active (Mac chrome-btn.sel)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
