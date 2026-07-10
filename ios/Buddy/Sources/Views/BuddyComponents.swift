import SwiftUI
import UIKit

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
                .accessibilityIdentifier("sheet-close")   // UI tests drive the close by id
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
    // Faintest sheet text (the version footer): black/30, white/40 on red.
    var sheetGhost: Color { level == .lvl2 ? Color.white.opacity(0.4)  : Color.black.opacity(0.3) }
}

// MARK: - Swipeable row
// The Mac reveals row actions on hover; the iPhone has no hover, so we use swipe (the
// user's pick). Native `.swipeActions` only works inside a List — which can't do the
// equal-height flex rows — so this is a custom swipe that preserves the layout.
//   swipe LEFT → checkmark · calendar (sleep) · X (delete) · tap → onTap (edit)
// Mac-parity motion: the sheet slide uses the EXACT Mac curves (dist/index.html
// :root) — open = --ease-out cubic-bezier(0.23,1,0.32,1) over .42s (fast → slow
// at the top); close = --ease-in cubic-bezier(0.68,0,0.77,0) over .32s (slow →
// fast toward the bottom). One source for every open/close call site.
enum BuddyAnim {
    static let sheetOpen  = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.42)
    static let sheetClose = Animation.timingCurve(0.68, 0, 0.77, 0, duration: 0.32)
}

struct SwipeableRow<Content: View>: View {
    var rowID: String                   // identity, so only one row stays open at a time
    @Binding var openRowID: String?     // shared: which row is currently open
    var theme: EscalationTheme          // card fill + tray/divider/glyph tokens (RULE 1)
    var onComplete: (() -> Void)? = nil
    var onAdd: (() -> Void)? = nil       // future rows: swipe → add to today
    var onSleep: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onRestore: (() -> Void)? = nil  // done rows: swipe → undo (back to to-do)
    var onTap: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    // Smooth swipe: track the live delta in @State (NOT @GestureState). @GestureState snaps
    // to 0 the instant the finger lifts — a frame before onEnded's settle — which is the jitter.
    @State private var offset: CGFloat = 0     // committed rest offset (0 or -openWidth)
    @State private var drag: CGFloat = 0       // live finger delta during a drag

    private let actionW: CGFloat = 58          // ≥ 44pt (Apple's min tap target)
    private let settle   = Animation.easeOut(duration: 0.2)   // fast, no spring bounce (shadcn-ish)

    // Trailing actions, left→right: checkmark · calendar (move to Future) · X (remove).
    private var actions: [(icon: String, run: () -> Void)] {
        var a: [(String, () -> Void)] = []
        if let onRestore  { a.append(("undo", onRestore)) }   // done rows: rewind to to-do
        if let onAdd      { a.append(("plus", onAdd)) }
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
                    if i > 0 { theme.swipeDivider.frame(width: 1).frame(maxHeight: .infinity) }
                    Button { fire(act.run) } label: {
                        LucideIcon(act.icon, size: 22)
                            .foregroundStyle(theme.glyph)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(theme.swipeActionBg)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: actionW)
                    .accessibilityIdentifier("swipe-\(act.icon)")   // UI tests tap tray actions by id
                }
            }

            // Content on top — opaque, so it hides the actions at rest; offset reveals them.
            // The swipe is a UIKIT pan, not a SwiftUI DragGesture: ANY SwiftUI drag on a
            // row (high-priority OR simultaneous) starves the enclosing ScrollView's pan
            // and the Future list stops scrolling — verified empirically via the
            // `-noSwipe` experiment switch (RULE 4). The UIKit recognizer begins ONLY on
            // horizontal movement, so vertical drags stay with the ScrollView.
            // ORDER IS LOAD-BEARING: the pan-catcher overlay goes on BEFORE .offset so
            // it slides WITH the content. Overlaid after .offset it stays on the row's
            // layout frame, covers the revealed tray, and its tap handler eats every
            // action-button tap (field report 2026-07-10: "swipe shows, doesn't act").
            let base = content()
                .background(theme.cardBackground)
            Group {
                if ProcessInfo.processInfo.arguments.contains("-noSwipe") {
                    base.onTapGesture { if offset != 0 { close() } else { onTap?() } }
                } else {
                    base.overlay(
                        HorizontalPanCatcher(
                            onChanged: { tx in drag = tx },   // 1:1 with the finger, no animation
                            onEnded: { tx in
                                let willOpen = (offset + tx) < -openWidth * 0.5
                                withAnimation(settle) { offset = willOpen ? -openWidth : 0; drag = 0 }
                                if willOpen { openRowID = rowID }
                                else if openRowID == rowID { openRowID = nil }
                            },
                            onTap: { if offset != 0 { close() } else { onTap?() } }
                        )
                    )
                }
            }
            .offset(x: x)
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

// A UIKit pan that begins ONLY on horizontal movement and coexists with the
// UIScrollView pan. This is the load-bearing piece of SwipeableRow: SwiftUI
// DragGestures (any priority) block the enclosing ScrollView from scrolling,
// so row swipes MUST live at the UIKit layer. A tap recognizer rides along so
// tap-to-edit keeps working (the overlay sits above the row's content).
private struct HorizontalPanCatcher: UIViewRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void
    var onTap: () -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        v.addGestureRecognizer(tap)
        return v
    }

    func updateUIView(_ view: UIView, context: Context) { context.coordinator.parent = self }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HorizontalPanCatcher
        init(_ parent: HorizontalPanCatcher) { self.parent = parent }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            // Measure in the WINDOW, not g.view: the overlay slides with the row,
            // so translations in its own space are fed back on themselves — the
            // row lags the finger and modest pulls land under the open threshold
            // and spring back ("bounces, needs two pulls", field report 2026-07-10).
            let space = g.view?.window
            let t = g.translation(in: space)
            switch g.state {
            case .changed: parent.onChanged(t.x)
            case .ended, .cancelled, .failed: parent.onEnded(t.x)
            default: break
            }
        }
        @objc func tap(_ g: UITapGestureRecognizer) {
            if g.state == .ended { parent.onTap() }
        }
        // Horizontal starts only — a vertical start FAILS here, so the ScrollView
        // scrolls. Prefer the TRANSLATION accumulated during the hysteresis
        // distance (stable) over instantaneous velocity (noisy on slow pulls);
        // fall back to velocity only when translation is degenerate.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let t = pan.translation(in: pan.view?.window)
            if abs(t.x) + abs(t.y) > 2 { return abs(t.x) > abs(t.y) }
            let v = pan.velocity(in: pan.view?.window)
            return abs(v.x) > abs(v.y)
        }
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
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
