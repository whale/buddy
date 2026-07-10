import SwiftUI
import UIKit

// MARK: - CelebrationView
// Physics celebration — the SAME constants and equations as the Mac
// (dist/index.html CELEB/QUIET, tuned in design/celebration-lab.html, preset
// "Whale ✦ picked" 2026-07-10). A real ballistic model (velocity + gravity +
// linear drag), not keyframes, so the arc has momentum.
//
// intensity == 0 → the QUIET POP: one random yellow hand floats ~70pt up from
// the completed row's checkmark, fading in fast and out slow.
// intensity 1…100 → the burst: count and emoji variety scale with intensity.
struct CelebrationView: View {
    let intensity: Int              // 0–100 (settings.celebrate)
    var anchor: CGPoint? = nil      // quiet-pop origin (the row's ✓), screen coords
    var onFinish: () -> Void = {}

    var body: some View {
        Group {
            if intensity <= 0 {
                QuietPop(anchor: anchor, onFinish: onFinish)
            } else {
                PhysicsBurst(intensity: intensity, onFinish: onFinish)
            }
        }
        .allowsHitTesting(false)
    }
}

// Shared constants — keep in lockstep with the Mac's CELEB/QUIET/pools.
enum CelebPhysics {
    static let speed: Double = 1400, speedJit = 0.98
    static let angle: Double = 43, spread: Double = 39
    static let gravity: Double = 1500, drag: Double = 0.6
    static let spin: Double = 630
    static let sizeMin: Double = 16, sizeMax: Double = 44
    static let life: Double = 6.0, fadeJit = 0.77
    static let stagger: Double = 0.44
    static let count = 120
    static let labWidth: Double = 940      // horizontal reach scales to panel width
    static let pool = ["🦜","👍","😀","😄","😁","😆","😊","🥳","🤩","😎","🙌"]

    static let quietRise: Double = 70, quietDur: Double = 1.1
    static let quietInPct: Double = 0.18, quietSize: Double = 24, quietDrift: Double = 6
    static let hands = ["👍","🤘","💪","✊","🤜"]   // yellow default-tone only
}

// MARK: - The burst
private struct PhysicsBurst: View {
    let intensity: Int
    var onFinish: () -> Void

    private struct P {
        let glyph: String
        let x0, y0, vx0, vy0: Double      // launch state
        let rot0, vr: Double
        let size: Double
        let born: Double                   // stagger offset (s)
        let life, fadeAt: Double
    }
    @State private var parts: [P] = []
    @State private var start = Date()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { tl in
                Canvas { ctx, _ in
                    let t0 = tl.date.timeIntervalSince(start)
                    let k = CelebPhysics.drag, g = CelebPhysics.gravity
                    for p in parts {
                        let t = t0 - p.born
                        guard t > 0, t < p.life else { continue }
                        // Closed-form ballistic with linear drag — the continuous
                        // curve the Mac's per-frame integrator approximates.
                        let decay = 1 - exp(-k * t)
                        let x = p.x0 + (p.vx0 / k) * decay
                        let y = p.y0 + ((p.vy0 + g / k) / k) * decay - (g / k) * t
                        guard y < geo.size.height + 80 else { continue }
                        let alpha = t < p.fadeAt ? 1.0 : max(0, 1 - (t - p.fadeAt) / (p.life - p.fadeAt))
                        var glyph = ctx
                        glyph.opacity = alpha
                        glyph.translateBy(x: x, y: y)
                        glyph.rotate(by: .degrees(p.rot0 + p.vr * t))
                        glyph.draw(Text(p.glyph).font(.system(size: p.size)), at: .zero)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { launch() }
    }

    private func launch() {
        let i = Double(min(100, max(1, intensity))) / 100
        let count = max(3, Int((i * i * Double(CelebPhysics.count)).rounded()))
        let kinds = max(2, Int((2 + i * Double(CelebPhysics.pool.count - 2)).rounded()))
        let pool = Array(CelebPhysics.pool.prefix(kinds))
        let W = UIScreen.main.bounds.width, H = UIScreen.main.bounds.height
        let xs = min(1, W / CelebPhysics.labWidth)     // same narrow-stage rule as the Mac
        start = Date()
        parts = (0..<count).map { _ in
            let a = (CelebPhysics.angle + .random(in: -CelebPhysics.spread...CelebPhysics.spread)) * .pi / 180
            let sp = CelebPhysics.speed * (1 + .random(in: -CelebPhysics.speedJit...CelebPhysics.speedJit))
            let life = CelebPhysics.life * (1 - .random(in: 0...CelebPhysics.fadeJit) * 0.5)
            return P(glyph: pool.randomElement()!,
                     x0: 40, y0: H - 24,
                     vx0: cos(a) * sp * xs, vy0: -sin(a) * sp,
                     rot0: .random(in: 0...360), vr: .random(in: -CelebPhysics.spin...CelebPhysics.spin),
                     size: .random(in: CelebPhysics.sizeMin...CelebPhysics.sizeMax),
                     born: .random(in: 0...CelebPhysics.stagger),
                     life: life,
                     fadeAt: life * .random(in: 0.55...0.90))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + CelebPhysics.life + CelebPhysics.stagger + 0.3) {
            onFinish()
        }
    }
}

// MARK: - The quiet pop (minimum celebration)
private struct QuietPop: View {
    let anchor: CGPoint?
    var onFinish: () -> Void

    // Randomized without repeats across pops (matches the Mac's quietLastHand).
    private static var lastHand = -1
    @State private var glyph = "👍"
    @State private var drift: Double = 0
    @State private var start = Date()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { tl in
                let u = min(1, max(0, tl.date.timeIntervalSince(start) / CelebPhysics.quietDur))
                let eased = 1 - pow(1 - u, 4)          // ≈ the Mac's cubic-bezier(0.23,1,0.32,1)
                let inEnd = CelebPhysics.quietInPct
                let alpha = u < inEnd ? u / inEnd : max(0, 1 - (u - inEnd) / (1 - inEnd))
                let origin = anchor ?? CGPoint(x: geo.size.width - 64, y: geo.size.height * 0.55)
                Text(glyph)
                    .font(.system(size: CelebPhysics.quietSize))
                    .opacity(alpha)
                    .position(x: origin.x + drift * eased,
                              y: origin.y - CelebPhysics.quietSize - CelebPhysics.quietRise * eased)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            var i: Int
            repeat { i = Int.random(in: 0..<CelebPhysics.hands.count) } while i == Self.lastHand
            Self.lastHand = i
            glyph = CelebPhysics.hands[i]
            drift = .random(in: -CelebPhysics.quietDrift...CelebPhysics.quietDrift)
            start = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + CelebPhysics.quietDur + 0.1) { onFinish() }
        }
    }
}

// MARK: - Previews
#Preview("Burst") {
    ZStack {
        Color.white.ignoresSafeArea()
        CelebrationView(intensity: 100)
    }
}
#Preview("Quiet pop") {
    ZStack {
        Color.white.ignoresSafeArea()
        CelebrationView(intensity: 0, anchor: CGPoint(x: 340, y: 400))
    }
}
