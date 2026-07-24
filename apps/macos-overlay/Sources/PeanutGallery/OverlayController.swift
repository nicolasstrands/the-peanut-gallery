import AppKit

final class OverlayController {
    private var windows: [OverlayWindow] = []

    var isVisible: Bool { windows.first?.isVisible == true }

    func show() {
        windows = NSScreen.screens.map { OverlayWindow(screen: $0) }
        windows.forEach { $0.orderFrontRegardless() }
    }

    func toggle() {
        if windows.first?.isVisible == true { windows.forEach { $0.orderOut(nil) } }
        else { windows.forEach { $0.orderFrontRegardless() } }
    }

    func add(emoji: String) { windows.forEach { $0.overlayView.add(emoji: emoji) } }
}

final class OverlayWindow: NSPanel {
    let overlayView: OverlayView

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        overlayView = OverlayView(frame: contentRect)
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = overlayView
    }

    convenience init(screen: NSScreen) {
        self.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    }
}
