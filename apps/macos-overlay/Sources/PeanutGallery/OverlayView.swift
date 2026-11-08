import AppKit

final class OverlayView: NSView {
    private static let maxParticles = 160
    private static let reducedMotionLimit = 12

    private struct Particle {
        let emoji: String
        var x: CGFloat
        var y: CGFloat
        var age: CGFloat = 0
        let speed: CGFloat
        let drift: CGFloat
        let attributes: [NSAttributedString.Key: Any]
    }

    private var particles: [Particle] = []
    private var timer: Timer?
    private var lastTick: TimeInterval?
    private var reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { timer?.invalidate() }

    func add(emoji: String) {
        guard !emoji.isEmpty, bounds.width > 80, bounds.height > 80 else { return }
        updateMotionPreference()
        let size = CGFloat.random(in: 40...64)
        let particle = Particle(
            emoji: emoji,
            x: CGFloat.random(in: 40...(bounds.width - 40)),
            y: reducedMotion ? CGFloat.random(in: 20...max(20, min(140, bounds.height - 70))) : -70,
            speed: CGFloat.random(in: 108...240),
            drift: CGFloat.random(in: -48...48),
            attributes: [.font: NSFont.systemFont(ofSize: size)]
        )
        let limit = reducedMotion ? Self.reducedMotionLimit : Self.maxParticles
        if particles.count >= limit { particles.removeFirst(particles.count - limit + 1) }
        particles.append(particle)
        if timer == nil {
            lastTick = ProcessInfo.processInfo.systemUptime
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
                [weak self] _ in
                self?.tick()
            }
        }
        needsDisplay = true
    }

    private func updateMotionPreference() {
        let preference = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard preference != reducedMotion else { return }
        reducedMotion = preference
        particles.removeAll()
        needsDisplay = true
    }

    private func tick() {
        updateMotionPreference()
        let now = ProcessInfo.processInfo.systemUptime
        // Measure real time rather than frames; cap long pauses after sleep.
        let elapsed = CGFloat(min(max(now - (lastTick ?? now), 0), 0.1))
        lastTick = now
        for index in particles.indices {
            particles[index].age += elapsed
            if !reducedMotion {
                particles[index].y += particles[index].speed * elapsed
                particles[index].x +=
                    sin(particles[index].age / 0.3) * particles[index].drift * elapsed
            }
        }
        particles.removeAll { reducedMotion ? $0.age >= 1.5 : $0.y >= bounds.height + 100 }
        // Redraw even when the last particle expires, so it cannot linger.
        needsDisplay = true
        if particles.isEmpty {
            timer?.invalidate()
            timer = nil
            lastTick = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        autoreleasepool {
            for particle in particles {
                NSGraphicsContext.saveGraphicsState()
                if reducedMotion {
                    let alpha = min(1, max(0, (1.5 - particle.age) / 0.3))
                    NSGraphicsContext.current?.cgContext.setAlpha(alpha)
                }
                NSString(string: particle.emoji).draw(
                    at: NSPoint(x: particle.x, y: particle.y),
                    withAttributes: particle.attributes
                )
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
}
