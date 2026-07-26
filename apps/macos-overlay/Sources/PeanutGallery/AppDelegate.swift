import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let roomDefaultsKey = "peanutGallery.roomID"
    private var statusItem: NSStatusItem!
    private var overlayController: OverlayController!
    private var leaderboardController: LeaderboardController!
    private var socket: ReactionSocket!
    private var statusMenuItem: NSMenuItem!
    private var connectionMenuItem: NSMenuItem!
    private var serverMenuItem: NSMenuItem!
    private var roomMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var leaderboardToggleMenuItem: NSMenuItem!
    private var connectionState: ReactionConnectionState = .disconnected

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        overlayController = OverlayController()
        overlayController.show()
        leaderboardController = LeaderboardController()
        leaderboardController.show()
        socket = ReactionSocket(onReaction: { [weak self] emoji in
            DispatchQueue.main.async { self?.overlayController.add(emoji: emoji) }
        }, onLeaderboard: { [weak self] counts in
            DispatchQueue.main.async { self?.leaderboardController.update(counts: counts) }
        }, onStateChange: { [weak self] state in
            DispatchQueue.main.async { self?.updateConnectionStatus(state) }
        })
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.length = NSStatusItem.variableLength
        updateStatusIcon(active: true)
        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Status: Active", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        connectionMenuItem = NSMenuItem(title: "Connection: Disconnected", action: nil, keyEquivalent: "")
        connectionMenuItem.isEnabled = false
        menu.addItem(connectionMenuItem)
        serverMenuItem = NSMenuItem(title: "Server: Not configured", action: nil, keyEquivalent: "")
        serverMenuItem.isEnabled = false
        menu.addItem(serverMenuItem)
        roomMenuItem = NSMenuItem(title: "Room: None selected", action: nil, keyEquivalent: "")
        roomMenuItem.isEnabled = false
        menu.addItem(roomMenuItem)
        menu.addItem(.separator())
        let serverItem = NSMenuItem(title: "Set Realtime Server…", action: #selector(configureServer), keyEquivalent: "s")
        serverItem.target = self
        menu.addItem(serverItem)
        let connectItem = NSMenuItem(title: "Connect to Room…", action: #selector(connectToRoom), keyEquivalent: "c")
        connectItem.target = self
        menu.addItem(connectItem)
        let disconnectItem = NSMenuItem(title: "Disconnect", action: #selector(disconnect), keyEquivalent: "d")
        disconnectItem.target = self
        menu.addItem(disconnectItem)
        toggleMenuItem = NSMenuItem(title: "Hide Overlay", action: #selector(toggleOverlay), keyEquivalent: "h")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)
        leaderboardToggleMenuItem = NSMenuItem(title: "Hide Leaderboard", action: #selector(toggleLeaderboard), keyEquivalent: "l")
        leaderboardToggleMenuItem.target = self
        menu.addItem(leaderboardToggleMenuItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Peanut Gallery", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        updateServerMenuItem()

        if RealtimeSettings.resolvedURL == nil {
            // First run: the overlay cannot do anything useful until it knows
            // where to connect, so ask instead of failing silently.
            updateConnectionStatus(.unconfigured)
            DispatchQueue.main.async { [weak self] in self?.configureServer() }
        } else if let savedRoom = UserDefaults.standard.string(forKey: roomDefaultsKey) {
            connect(to: savedRoom)
        }
    }

    @objc private func configureServer() {
        if RealtimeSettings.isOverriddenByEnvironment {
            let alert = NSAlert()
            alert.messageText = "Server set by the environment"
            alert.informativeText = """
                PEANUT_GALLERY_REALTIME_URL is set to \(RealtimeSettings.resolvedURL ?? ""), \
                which overrides anything saved here. Unset it and relaunch to edit the server \
                from this menu.
                """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Realtime server"
        alert.informativeText = """
            Paste the address of your Peanut Gallery realtime Worker.
            """
        alert.alertStyle = .informational
        let field = NSTextField(string: RealtimeSettings.storedURL ?? "")
        field.placeholderString = "wss://peanut-gallery-realtime.<subdomain>.workers.dev"
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        field.menu = editingMenu()
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let normalized = RealtimeSettings.normalized(field.stringValue) else {
            showServerError()
            return
        }

        RealtimeSettings.store(normalized)
        updateServerMenuItem()

        // Reconnect so the change takes effect without a relaunch.
        if let room = UserDefaults.standard.string(forKey: roomDefaultsKey), !room.isEmpty {
            connect(to: room)
        } else {
            updateConnectionStatus(.disconnected)
        }
    }

    private func editingMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        return menu
    }

    private func updateServerMenuItem() {
        guard let url = RealtimeSettings.resolvedURL else {
            serverMenuItem?.title = "Server: Not configured"
            serverMenuItem?.toolTip = nil
            return
        }
        let suffix = RealtimeSettings.isOverriddenByEnvironment ? " (from environment)" : ""
        serverMenuItem?.title = "Server: \(RealtimeSettings.displayName(for: url))\(suffix)"
        // The title is abbreviated, so keep the full address one hover away.
        serverMenuItem?.toolTip = url
    }

    private func showServerError() {
        let alert = NSAlert()
        alert.messageText = "Invalid server address"
        alert.informativeText = """
            Enter a host or URL such as wss://peanut-gallery-realtime.example.workers.dev \
            or ws://localhost:8787, without a query string.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func connectToRoom() {
        // A room code is meaningless without a server, so collect that first.
        if RealtimeSettings.resolvedURL == nil {
            configureServer()
            guard RealtimeSettings.resolvedURL != nil else { return }
        }

        let alert = NSAlert()
        alert.messageText = "Connect to a room"
        alert.informativeText = "Enter the room code shared by the host."
        alert.alertStyle = .informational
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
        guard isValidRoomCode(room) else {
            showRoomError()
            return
        }
        connect(to: room)
    }

    private func connect(to room: String) {
        UserDefaults.standard.set(room, forKey: roomDefaultsKey)
        roomMenuItem?.title = "Room: \(room)"
        socket.connect(room: room)
    }

    @objc private func disconnect() {
        socket.disconnect()
        UserDefaults.standard.removeObject(forKey: roomDefaultsKey)
        roomMenuItem?.title = "Room: None selected"
    }

    private func isValidRoomCode(_ room: String) -> Bool {
        guard (3...64).contains(room.count) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return room.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func defaultRoomCode() -> String {
        if let clipboard = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           clipboard.count == 6,
           clipboard.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
            return clipboard.uppercased()
        }
        return UserDefaults.standard.string(forKey: roomDefaultsKey) ?? ""
    }

    private func showRoomError() {
        let alert = NSAlert()
        alert.messageText = "Invalid room code"
        alert.informativeText = "Use 3–64 letters, numbers, hyphens, or underscores."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func updateConnectionStatus(_ state: ReactionConnectionState) {
        connectionState = state
        let title: String
        switch state {
        case .connecting: title = "Connection: Connecting…"
        case .connected: title = "Connection: Connected"
        case .reconnecting: title = "Connection: Reconnecting…"
        case .disconnected: title = "Connection: Disconnected"
        case .unconfigured: title = "Connection: No server configured"
        }
        connectionMenuItem?.title = title
        updateStatusIcon(active: overlayController.isVisible)
    }
    @objc private func toggleOverlay() {
        overlayController.toggle()
        let active = overlayController.isVisible
        updateStatusIcon(active: active)
        statusMenuItem.title = active ? "Status: Active" : "Status: Paused"
        toggleMenuItem.title = active ? "Hide Overlay" : "Show Overlay"
    }

    @objc private func toggleLeaderboard() {
        leaderboardController.toggle()
        leaderboardToggleMenuItem.title = leaderboardController.isVisible ? "Hide Leaderboard" : "Show Leaderboard"
    }

    private func updateStatusIcon(active: Bool) {
        let indicator = active ? "●" : "○"
        let color: NSColor
        switch connectionState {
        case .connected:
            color = .systemGreen
        case .disconnected:
            color = .systemRed
        case .connecting, .reconnecting:
            color = .systemOrange
        case .unconfigured:
            color = .systemGray
        }
        statusItem.button?.image = nil
        statusItem.button?.attributedTitle = NSAttributedString(
            string: "\(indicator) 🥜",
            attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 14)]
        )
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
