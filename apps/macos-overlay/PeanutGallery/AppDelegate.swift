import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let roomDefaultsKey = "peanutGallery.roomID"
    private var statusItem: NSStatusItem!
    private var overlayController: OverlayController!
    private var socket: ReactionSocket!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        overlayController = OverlayController()
        overlayController.show()

        socket = ReactionSocket { [weak self] emoji in
            DispatchQueue.main.async { self?.overlayController.add(emoji: emoji) }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "🥜"
        let menu = NSMenu()
        let connectItem = NSMenuItem(title: "Connect to Room…", action: #selector(connectToRoom), keyEquivalent: "c")
        connectItem.target = self
        menu.addItem(connectItem)
        let disconnectItem = NSMenuItem(title: "Disconnect", action: #selector(disconnect), keyEquivalent: "d")
        disconnectItem.target = self
        menu.addItem(disconnectItem)
        menu.addItem(NSMenuItem(title: "Hide Overlay", action: #selector(toggleOverlay), keyEquivalent: "h"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Peanut Gallery", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        if let savedRoom = UserDefaults.standard.string(forKey: roomDefaultsKey) {
            socket.connect(room: savedRoom)
        }
    }

    @objc private func connectToRoom() {
        let alert = NSAlert()
        alert.messageText = "Connect to a room"
        alert.informativeText = "Enter the room code shared by the host."
        let field = NSTextField(string: defaultRoomCode())
        field.placeholderString = "e.g. ABC123"
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let room = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard (3...64).contains(room.count), room.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            let error = NSAlert()
            error.messageText = "Invalid room code"
            error.informativeText = "Use 3–64 letters, numbers, hyphens, or underscores."
            error.runModal()
            return
        }
        UserDefaults.standard.set(room, forKey: roomDefaultsKey)
        socket.connect(room: room)
    }

    @objc private func disconnect() {
        socket.disconnect()
        UserDefaults.standard.removeObject(forKey: roomDefaultsKey)
    }

    private func defaultRoomCode() -> String {
        if let clipboard = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           clipboard.count == 6,
           clipboard.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
            return clipboard.uppercased()
        }
        return UserDefaults.standard.string(forKey: roomDefaultsKey) ?? ""
    }

    @objc private func toggleOverlay() {
        overlayController.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
