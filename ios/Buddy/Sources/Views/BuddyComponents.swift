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
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))   // Figma spec
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
                        .frame(width: 36, height: 36, alignment: .trailing)   // glyph hugs the 32pt gutter
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)   // match the rows' 32pt gutter on both sides
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
//   swipe LEFT → checkmark · calendar (sleep) · X (delete) · tap → onTap (edit)
struct SwipeableRow<Content: View>: View {
    var rowID: String                   // identity, so only one row stays open at a time
    @Binding var openRowID: String?     // shared: which row is currently open
    var cardFill: Color                 // opaque row bg so the actions hide when closed
    var onComplete: (() -> Void)? = nil
    var onSleep: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onRestore: (() -> Void)? = nil  // done rows: swipe → undo (back to to-do)
    var onTap: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    // Smooth swipe: track the live delta in @State (NOT @GestureState). @GestureState snaps
    // to 0 the instant the finger lifts — a frame before onEnded's settle — which is the jitter.
    @State private var offset: CGFloat = 0     // committed rest offset (0 or -openWidth)
    @State private var drag: CGFloat = 0       // live finger delta during a drag
    @State private var locked = false          // gesture committed to horizontal

    private let actionW: CGFloat = 58          // ≥ 44pt (Apple's min tap target)
    private let actionBG = Color(hex: "#ececec")
    private let dividerC = Color(hex: "#c9c9c9")
    private let settle   = Animation.easeOut(duration: 0.2)   // fast, no spring bounce (shadcn-ish)

    // Trailing actions, left→right: checkmark · calendar (move to Future) · X (remove).
    private var actions: [(icon: String, run: () -> Void)] {
        var a: [(String, () -> Void)] = []
        if let onRestore  { a.append(("undo", onRestore)) }   // done rows: rewind to to-do
        if let onComplete { a.append(("check", onComplete)) }
        if let onSleep    { a.append(("calendar", onSleep)) }
        if let onDelete   { a.append(("x", onDelete)) }
        return a
    }
    private var openWidth: CGFloat { CGFloat(actions.count) * actionW + CGFloat(max(0, actions.count - 1)) }
    private var x: CGFloat { min(0, max(-openWidth, offset + drag)) }   // left-only, clamped

    var body: some View {
        ZStack {
            // Actions behind, pushed to the trailing edge (revealed as the content slides left).
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(Array(actions.enumerated()), id: \.offset) { i, act in
                    if i > 0 { dividerC.frame(width: 1).frame(maxHeight: .infinity) }
                    Button { fire(act.run) } label: {
                        LucideIcon(act.icon, size: 22)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(actionBG)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: actionW)
                }
            }

            // Content on top — opaque, so it hides the actions at rest; offset reveals them.
            content()
                .background(cardFill)
                .offset(x: x)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { v in
                            if !locked && abs(v.translation.width) > abs(v.translation.height) { locked = true }
                            if locked { drag = v.translation.width }   // 1:1 with the finger, no animation
                        }
                        .onEnded { v in
                            let willOpen = (offset + v.translation.width) < -openWidth * 0.5
                            withAnimation(settle) { offset = willOpen ? -openWidth : 0; drag = 0 }
                            if willOpen { openRowID = rowID }
                            else if openRowID == rowID { openRowID = nil }
                            locked = false
                        }
                )
                .onTapGesture {
                    if offset != 0 { close() } else { onTap?() }
                }
        }
        .clipped()
        // Another row opened → close this one.
        .onChange(of: openRowID) { _, newVal in
            if newVal != rowID && offset != 0 { withAnimation(settle) { offset = 0 } }
        }
        #if DEBUG
        .onAppear {   // screenshot harness: -uiSwipeOpen 1 reveals the actions
            if UserDefaults.standard.bool(forKey: "uiSwipeOpen") { offset = -openWidth }
        }
        #endif
    }

    private func close() {
        withAnimation(settle) { offset = 0 }
        if openRowID == rowID { openRowID = nil }
    }
    private func fire(_ action: @escaping () -> Void) {
        action()
        close()
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
