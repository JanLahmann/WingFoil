import SwiftUI

/// A one-shot confetti burst, drawn as a single `Canvas`.
///
/// No dependency and no particle *views*: a hundred `Rectangle`s would be a hundred nodes
/// in the view tree for two seconds. Each particle is a deterministic function of its seed
/// and the elapsed time, so nothing has to be stepped or stored — `TimelineView` supplies
/// the clock and the whole burst is one draw call per frame.
struct ConfettiBurst: View {

    /// Bumping this restarts the burst; nil shows nothing.
    let trigger: Int?
    var colors: [Color] = Brand.celebration
    var particleCount = 90
    var duration: Double = 2.4

    @State private var startedAt: Date?
    @State private var seed = 0

    var body: some View {
        Group {
            if let startedAt {
                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(startedAt)
                    Canvas { context, size in
                        draw(in: context, size: size, elapsed: elapsed)
                    }
                    .task(id: elapsed > duration) {
                        // Tear the whole thing down once it has played, so no timeline
                        // keeps ticking behind a static screen.
                        if elapsed > duration { self.startedAt = nil }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            guard trigger != nil else { return }
            seed &+= 1
            startedAt = Date()
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize, elapsed: Double) {
        guard elapsed <= duration else { return }
        // Fade the last third rather than cutting to nothing.
        let fade = elapsed > duration * 0.66
            ? max(0, 1 - (elapsed - duration * 0.66) / (duration * 0.34))
            : 1

        for index in 0..<particleCount {
            var random = Random(seed: UInt64(truncatingIfNeeded:
                seed &* 7919 &+ index &* 104_729 &+ 17))
            // Launched from two points near the top corners of the content, the way a
            // party popper actually throws — a rain of confetti from the top edge reads
            // as weather, not as a celebration.
            let fromLeft = index % 2 == 0
            let originX = size.width * (fromLeft ? 0.18 : 0.82)
            let originY = size.height * 0.28

            let angle = (fromLeft ? -0.35 : Double.pi + 0.35)
                + random.next(-0.9, 0.9)
            let speed = random.next(220, 620)
            let gravity = random.next(520, 900)

            let x = originX + cos(angle) * speed * elapsed
            let y = originY + sin(angle) * speed * elapsed + 0.5 * gravity * elapsed * elapsed
            guard y < size.height + 40 else { continue }

            let spin = random.next(-8, 8) * elapsed
            let width = random.next(4, 9)
            let height = width * random.next(0.4, 1.1)
            let color = colors[index % colors.count]

            var slip = context
            slip.opacity = fade * random.next(0.75, 1)
            slip.translateBy(x: x, y: y)
            slip.rotate(by: .radians(spin))
            // A flat rectangle spinning about its centre reads as a tumbling paper chip.
            slip.scaleBy(x: cos(spin * 1.7), y: 1)
            slip.fill(Path(CGRect(x: -width / 2, y: -height / 2,
                                  width: width, height: height)),
                      with: .color(color))
        }
    }
}

/// A tiny deterministic PRNG (splitmix64), so a particle's whole trajectory is a pure
/// function of its index — no per-frame state, and a burst looks the same if a redraw
/// happens to land twice on the same instant.
private struct Random {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next(_ lower: Double, _ upper: Double) -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        let unit = Double(z >> 11) / Double(UInt64(1) << 53)
        return lower + unit * (upper - lower)
    }
}
