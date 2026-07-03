import SwiftUI

// MARK: - Lucide glyph
// The Mac uses Lucide icons (stroke 1.8), NOT SF Symbols. These are the real Lucide
// SVGs converted to tintable vector PDFs (assets `lucide-<name>`), so the shapes match
// exactly. Tint via `.foregroundStyle(...)` on the caller.
struct LucideIcon: View {
    let name: String
    let size: CGFloat
    init(_ name: String, size: CGFloat) { self.name = name; self.size = size }
    var body: some View {
        Image("lucide-\(name)").renderingMode(.template).resizable().scaledToFit()
            .frame(width: size, height: size)
    }
}

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
                    LucideIcon("x", size: 16)
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
        if let onSleep  { a.append(("sleep", Color(hex: "#6b6b6b"), onSleep)) }   // Lucide calendar-arrow (Move to Future)
        if let onDelete { a.append(("x",     Color(hex: "#c62828"), onDelete)) }  // Lucide X (remove)
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
                    actionButton("check", Color(hex: "#30a46c")) { run(onComplete) }
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
                // (leading complete uses Lucide "check" — see actionButton)
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
            bg.overlay(LucideIcon(icon, size: 22).foregroundStyle(.white))
        }
        .buttonStyle(.plain)
        .frame(maxHeight: .infinity)
    }

    private func run(_ a: @escaping () -> Void) {
        a()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { offset = 0 }
    }
}

// MARK: - Buddy slider
// The Mac's `.buddy-range`: a thin 6px grey track + an 18px solid thumb, with NO filled
// progress bar (the native SwiftUI Slider draws a heavy tinted fill). Grey track + solid
// thumb, adapting to the level.
struct BuddySlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    var track: Color
    var thumb: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = range.upperBound - range.lowerBound
            let frac = span == 0 ? 0 : (value - range.lowerBound) / span
            ZStack(alignment: .leading) {
                Capsule().fill(track).frame(height: 6)
                Circle().fill(thumb).frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                    .offset(x: CGFloat(frac) * max(0, w - 18))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let x = min(max(0, g.location.x - 9), w - 18)
                    let f = (w - 18) <= 0 ? 0 : x / (w - 18)
                    value = range.lowerBound + Double(f) * span
                }
            )
        }
        .frame(height: 18)
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
            LucideIcon(systemName, size: size)   // real Lucide glyph, not an SF Symbol
                .foregroundStyle(selected ? selInk : ink)
                .frame(width: 39, height: 39)
                .background(selected ? selBg : .clear, in: Circle())   // filled circle when active (Mac chrome-btn.sel)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
