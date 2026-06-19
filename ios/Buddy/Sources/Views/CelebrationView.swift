import SwiftUI

// MARK: - CelebrationView
// A calm, one-shot confetti burst — emoji particles that arc upward and fade.
// Mirrors the Mac app's party-parrot confetti (§3.3), adapted for SwiftUI.
// Intensity comes from settings.celebrate (0–100).
// Fires ONLY on a transition into `done`; never on re-render.
struct CelebrationView: View {
    let intensity: Int              // 0–100
    var onFinish: () -> Void = {}

    @State private var particles: [Particle] = []
    @State private var visible = true

    private let emojis = ["👍🏼", "🦜", "✨", "🎉", "⭐️"]

    var body: some View {
        ZStack {
            if visible {
                ForEach(particles) { p in
                    Text(p.emoji)
                        .font(.system(size: p.size))
                        .position(p.position)
                        .opacity(p.opacity)
                        .rotationEffect(.degrees(p.rotation))
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { launch() }
    }

    private func launch() {
        guard intensity > 0 else { onFinish(); return }

        let count = max(1, Int(Double(intensity) / 100.0 * 40))
        let screenWidth  = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let origin = CGPoint(x: screenWidth * 0.85, y: screenHeight * 0.85)

        particles = (0..<count).map { _ in
            Particle(
                emoji: emojis.randomElement()!,
                position: origin,
                size: CGFloat.random(in: 18...28),
                opacity: 1,
                rotation: Double.random(in: -180...180)
            )
        }

        // Animate each particle outward
        for i in particles.indices {
            let delay = Double.random(in: 0...0.4)
            let dx = CGFloat.random(in: -screenWidth * 0.9 ... -screenWidth * 0.1)
            let dy = CGFloat.random(in: -screenHeight * 0.6 ... -screenHeight * 0.15)
            let duration = Double.random(in: 1.0...1.8)

            withAnimation(
                .easeOut(duration: duration).delay(delay)
            ) {
                particles[i].position = CGPoint(
                    x: origin.x + dx,
                    y: origin.y + dy
                )
                particles[i].rotation += Double.random(in: -260...260)
            }

            withAnimation(
                .linear(duration: 0.3).delay(delay + duration * 0.7)
            ) {
                particles[i].opacity = 0
            }
        }

        // Clean up after the longest possible animation
        let cleanup = 0.4 + 1.8 + 0.3 + 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + cleanup) {
            visible = false
            onFinish()
        }
    }
}

// MARK: - Particle model
private struct Particle: Identifiable {
    let id = UUID()
    var emoji: String
    var position: CGPoint
    var size: CGFloat
    var opacity: Double
    var rotation: Double
}

// MARK: - Previews
#Preview {
    ZStack {
        Color.white.ignoresSafeArea()
        CelebrationView(intensity: 80)
    }
}
