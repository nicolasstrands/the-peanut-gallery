import AppKit

final class LeaderboardController {
    private var panel: LeaderboardPanel?

    var isVisible: Bool { panel?.isVisible == true }

    func show() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        if panel == nil {
            panel = LeaderboardPanel(screen: screen)
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func update(counts: [String: Int]) {
        panel?.leaderboardView.update(counts: counts)
    }
}

final class LeaderboardPanel: NSPanel {
    let leaderboardView: LeaderboardView

    init(screen: NSScreen) {
            let size = NSSize(width: 220, height: 240)
        let frame = NSRect(
            x: screen.visibleFrame.maxX - size.width - 24,
            y: screen.visibleFrame.maxY - size.height - 24,
            width: size.width,
            height: size.height
        )
        leaderboardView = LeaderboardView(frame: NSRect(origin: .zero, size: size))
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
            ignoresMouseEvents = false
            isMovableByWindowBackground = false
            acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = leaderboardView
    }
}

    final class LeaderboardView: NSView {
        private var counts: [String: Int] = [:]
        private var dragStart: NSPoint?

        func update(counts: [String: Int]) {
            self.counts = counts
            needsDisplay = true
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            dragStart = event.locationInWindow
            NSCursor.closedHand.push()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragStart, let window else { return }

            let current = event.locationInWindow
            let origin = window.frame.origin
            window.setFrameOrigin(NSPoint(
                x: origin.x + current.x - dragStart.x,
                y: origin.y + current.y - dragStart.y
            ))
        }

        override func mouseUp(with event: NSEvent) {
            dragStart = nil
            NSCursor.pop()
        }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds.insetBy(dx: 1, dy: 1)
        let panelPath = NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18)
        NSColor(calibratedWhite: 0.08, alpha: 0.94).setFill()
        panelPath.fill()
        NSColor(calibratedRed: 0.96, green: 0.72, blue: 0.24, alpha: 0.65).setStroke()
        panelPath.lineWidth = 1
        panelPath.stroke()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor(calibratedWhite: 0.98, alpha: 1)
        ]
        NSString(string: "Room leaderboard").draw(
            at: NSPoint(x: 18, y: bounds.maxY - 34),
            withAttributes: titleAttributes
        )

        let rows = counts.sorted { left, right in
            if left.value == right.value { return left.key < right.key }
            return left.value > right.value
        }.prefix(5)

        if rows.isEmpty {
            let emptyAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor(calibratedWhite: 0.65, alpha: 1)
            ]
            NSString(string: "No reactions yet").draw(
                at: NSPoint(x: 18, y: bounds.midY - 8),
                withAttributes: emptyAttributes
            )
            return
        }

        for (index, row) in rows.enumerated() {
            let y = bounds.maxY - 70 - CGFloat(index * 32)
            let rankAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 12),
                .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1)
            ]
            let emojiAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 22),
                .foregroundColor: NSColor.white
            ]
            let countAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 14),
                .foregroundColor: NSColor(calibratedRed: 0.96, green: 0.72, blue: 0.24, alpha: 1)
            ]

            NSString(string: "\(index + 1)").draw(
                at: NSPoint(x: 18, y: y + 5),
                withAttributes: rankAttributes
            )
            NSString(string: row.key).draw(
                at: NSPoint(x: 48, y: y),
                withAttributes: emojiAttributes
            )

            let count = NSString(string: "\(row.value)")
            let countSize = count.size(withAttributes: countAttributes)
            count.draw(
                at: NSPoint(x: bounds.maxX - 18 - countSize.width, y: y + 5),
                withAttributes: countAttributes
            )
        }
    }
}
