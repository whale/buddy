import SwiftUI

// MARK: - FutureMoreCount
// The quiet "6 more ↓" in Future's pinned Add row (Mac .future-more / .fm-num).
// Motion in Buddy's language (Mac --ease-out cubic-bezier(0.23,1,0.32,1)):
//   • appears with Fade + Drift from 6pt right over 0.48s (--t-drift); leaves over 0.24s,
//     keeping its last number while it fades.
//   • a new number ROLLS: the old one slides out by ~60% of its height and fades (0.14s),
//     the new one slides in from the other side (0.18s). Up when the count drops (scrolling
//     down), down when it rises.
//   • Reduce Motion → opacity only (and the outgoing number just goes).
// State lives in the PARENT (HistoryView), so a rebuilt Add row lands already showing the
// current count — no replay / flash on re-render (Mac's `.still`).
enum BuddyEase {
    static func out(_ d: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: d) }
    static let drift = 0.48
}

struct FutureMoreCount: View {
    let shown: Int            // the number on screen (kept while fading out)
    let visible: Bool
    let rollUp: Bool          // direction for the NEXT change of `shown`
    let fontSize: CGFloat
    let theme: EscalationTheme
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rollDistance: CGFloat { fontSize * 1.25 * 0.6 }   // ~60% of the line box

    private var roll: AnyTransition {
        if reduceMotion {
            return .asymmetric(insertion: .opacity.animation(BuddyEase.out(0.18)), removal: .identity)
        }
        let d = rollDistance
        let inFrom: CGFloat = rollUp ? d : -d      // up: new rises from below
        let outTo: CGFloat = rollUp ? -d : d       // up: old leaves upward
        return .asymmetric(
            insertion: .modifier(active: RollOffset(y: inFrom, opacity: 0), identity: RollOffset(y: 0, opacity: 1))
                .animation(BuddyEase.out(0.18)),
            removal: .modifier(active: RollOffset(y: outTo, opacity: 0), identity: RollOffset(y: 0, opacity: 1))
                .animation(BuddyEase.out(0.14)))
    }

    // Appear: Fade + Drift in from 6pt right over 0.48s. Leave: back out over 0.24s. As a
    // TRANSITION (not opacity on a live view) so a faded-out count is really gone — VoiceOver
    // and hit-testing included — while the leaving view still draws its last number.
    private var presence: AnyTransition {
        let drift: CGFloat = reduceMotion ? 0 : 6
        let away = RollOffset(x: drift, y: 0, opacity: 0), home = RollOffset(x: 0, y: 0, opacity: 1)
        return .asymmetric(insertion: .modifier(active: away, identity: home).animation(BuddyEase.out(BuddyEase.drift)),
                           removal: .modifier(active: away, identity: home).animation(BuddyEase.out(0.24)))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if visible {
                Button(action: action) {
                    HStack(spacing: 0) {
                        ZStack(alignment: .trailing) {
                            Text("\(shown)")
                                .id(shown)
                                .transition(roll)
                        }
                        .clipped()
                        Text(" more ↓")
                    }
                    .font(.geist(fontSize, .regular))
                    .tracking(-0.02 * fontSize)
                    .lineLimit(1)
                    .fixedSize()
                }
                .buttonStyle(MorePressStyle(theme: theme))
                .accessibilityLabel(shown == 1 ? "1 more item below" : "\(shown) more items below")
                .accessibilityHint("Scrolls to the bottom")
                .accessibilityIdentifier("future-more")
                .transition(presence)
            }
        }
    }
}

private struct RollOffset: ViewModifier {
    var x: CGFloat = 0
    let y: CGFloat
    let opacity: Double
    func body(content: Content) -> some View { content.offset(x: x, y: y).opacity(opacity) }
}

// Add-ink at rest, brighter (full ink) on press — Mac .future-more:hover → --addtxt-hover.
private struct MorePressStyle: ButtonStyle {
    let theme: EscalationTheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? theme.ink : theme.addInk)
            .contentShape(Rectangle())
            .padding(.vertical, 12)          // a comfortable tap target inside the Add row
            .contentShape(Rectangle())
    }
}
