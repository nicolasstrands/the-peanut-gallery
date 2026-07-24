import AppKit

final class OverlayView: NSView {
    private struct Particle {
        var emoji: String
        var x: CGFloat
        var y: CGFloat
        var age: CGFloat
        let speed: CGFloat
        let drift: CGFloat
        let size: CGFloat
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

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func add(emoji: String) {
        guard particles.count < 160 else { return }
        particles.append(Particle(emoji: emoji, x: CGFloat.random(in: 40...(bounds.width - 40)), y: -60, age: 0, speed: CGFloat.random(in: 1.8...4.0), drift: CGFloat.random(in: -0.8...0.8), size: CGFloat.random(in: 34...76)))
    }

    private func tick() {
        particles = particles.compactMap { particle in
            var item = particle
            item.age += 1
            item.y += item.speed
            item.x += sin(item.age / 18) * item.drift
            return item.y < bounds.height + 100 ? item : nil
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for particle in particles {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: particle.size)]
            NSString(string: particle.emoji).draw(at: NSPoint(x: particle.x, y: particle.y), withAttributes: attributes)
        }
    }
}
