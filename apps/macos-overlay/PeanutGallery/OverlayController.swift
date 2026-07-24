import AppKit

final class OverlayController {
    private var windows: [OverlayWindow] = []

    func show() {
        windows = NSScreen.screens.map { OverlayWindow(screen: $0) }
        windows.forEach { $0.orderFrontRegardless() }
    }

    func toggle() {
        if windows.first?.isVisible == true { windows.forEach { $0.orderOut(nil) } }
        else { windows.forEach { $0.orderFrontRegardless() } }
    }

    func add(emoji: String) {
        windows.forEach { $0.overlayView.add(emoji: emoji) }
    }
}

final class OverlayWindow: NSPanel {
    let overlayView: OverlayView

    init(screen: NSScreen) {
        overlayView = OverlayView(frame: screen.frame)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: screen)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = overlayView
    }
}
