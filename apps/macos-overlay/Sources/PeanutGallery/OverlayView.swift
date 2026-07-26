import AppKit

final class OverlayView: NSView {
    private static let maxParticles = 160

    private struct Particle {
        var emoji: String
        var x: CGFloat
        var y: CGFloat
        var age: CGFloat
        var speed: CGFloat
        var drift: CGFloat
        var size: CGFloat
        var attributes: [NSAttributedString.Key: Any]
    }

    private var particles: [Particle] = []
    private var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    func add(emoji: String) {
        guard !emoji.isEmpty, bounds.width > 80 else { return }

        let size = CGFloat.random(in: 34...76)
        let particle = Particle(
            emoji: emoji,
            x: CGFloat.random(in: 40...(bounds.width - 40)),
            y: -60,
            age: 0,
            speed: CGFloat.random(in: 1.8...4.0),
            drift: CGFloat.random(in: -0.8...0.8),
            size: size,
            attributes: [.font: NSFont.systemFont(ofSize: size)]
        )

        // Reuse the oldest particle when the pool is full. This keeps memory
        // and compositor work bounded during reaction bursts.
        if particles.count == Self.maxParticles {
            particles.removeFirst()
        }
        particles.append(particle)
        needsDisplay = true
    }

    private func tick() {
        guard !particles.isEmpty else { return }

        var index = particles.count
        while index > 0 {
            index -= 1
            particles[index].age += 1
            particles[index].y += particles[index].speed
            particles[index].x += sin(particles[index].age / 18) * particles[index].drift

            if particles[index].y >= bounds.height + 100 {
                particles.remove(at: index)
            }
        }

        if !particles.isEmpty {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        autoreleasepool {
            for particle in particles {
                NSString(string: particle.emoji).draw(
                    at: NSPoint(x: particle.x, y: particle.y),
                    withAttributes: particle.attributes
                )
            }
        }
    }
}
