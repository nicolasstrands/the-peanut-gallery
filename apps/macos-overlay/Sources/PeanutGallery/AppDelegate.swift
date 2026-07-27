import AppKit

/// AppKit dispatches undo and redo down the responder chain but declares no
/// Swift counterpart, so this exists only to give `#selector` something to name.
@objc private protocol UndoActions {
    func undo(_ sender: Any?)
    func redo(_ sender: Any?)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum DefaultsKey {
        static let room = "peanutGallery.roomID"
        /// Whether the last deliberate action was a connect rather than a
        /// disconnect. Kept apart from the room code so disconnecting can stop
        /// the socket without forgetting which room you were in.
        static let autoConnect = "peanutGallery.autoConnect"
    }

    private var statusItem: NSStatusItem!
    private var overlayController: OverlayController!
    private var leaderboardController: LeaderboardController!
    private var socket: ReactionSocket!
    private var settingsController: SettingsWindowController!

    private var statusMenuItem: NSMenuItem!
    private var connectionMenuItem: NSMenuItem!
    private var serverMenuItem: NSMenuItem!
    private var roomMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var leaderboardToggleMenuItem: NSMenuItem!

    private var connectionState: ReactionConnectionState = .disconnected

    private var savedRoom: String? {
        UserDefaults.standard.string(forKey: DefaultsKey.room).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// An absent key means the user has never disconnected, which keeps the
    /// previous behaviour for anyone upgrading.
    private var shouldAutoConnect: Bool {
        UserDefaults.standard.object(forKey: DefaultsKey.autoConnect) as? Bool ?? true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

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

        buildSettingsController()
        installStatusItem()
        restoreSession()
    }

    // MARK: - Setup

    /// An accessory app has no menu bar, and cut/copy/paste/select-all are menu
    /// key equivalents rather than key bindings. Without a menu the Settings
    /// fields silently ignore ⌘V, which is how a server address usually arrives.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Peanut Gallery", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: #selector(UndoActions.undo(_:)), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: #selector(UndoActions.redo(_:)), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = makeStatusMenu()
        updateStatusIcon(active: overlayController.isVisible)
        updateServerMenuItem()
        updateRoomMenuItem(savedRoom)
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()

        statusMenuItem = Self.readOnlyItem("Status: Active")
        connectionMenuItem = Self.readOnlyItem("Connection: Disconnected")
        serverMenuItem = Self.readOnlyItem("Server: Not configured")
        roomMenuItem = Self.readOnlyItem("Room: None selected")
        [statusMenuItem, connectionMenuItem, serverMenuItem, roomMenuItem].forEach(menu.addItem)

        menu.addItem(.separator())
        menu.addItem(item(title: "Settings…", action: #selector(openSettings), key: ","))
        toggleMenuItem = item(title: "Hide Overlay", action: #selector(toggleOverlay), key: "h")
        menu.addItem(toggleMenuItem)
        leaderboardToggleMenuItem = item(title: "Hide Leaderboard", action: #selector(toggleLeaderboard), key: "l")
        menu.addItem(leaderboardToggleMenuItem)

        menu.addItem(.separator())
        menu.addItem(item(title: "Quit Peanut Gallery", action: #selector(quit), key: "q"))

        return menu
    }

    private static func readOnlyItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func item(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func buildSettingsController() {
        settingsController = SettingsWindowController()

        settingsController.onServerChange = { [weak self] server in
            guard let self else { return }
            RealtimeSettings.store(server)
            self.updateServerMenuItem()
            // Re-dial the same room against the new address, but only for a
            // connection that was already live.
            if self.connectionState.isLive, let room = self.savedRoom {
                self.connect(to: room)
            }
        }
        settingsController.onConnect = { [weak self] room in self?.connect(to: room) }
        settingsController.onDisconnect = { [weak self] in self?.disconnect() }
        settingsController.onOverlayVisibilityChange = { [weak self] visible in
            self?.setOverlay(visible: visible)
        }
    }

    /// Reconnects to where the user left off, or opens Settings when there is
    /// nowhere to connect to yet.
    private func restoreSession() {
        guard RealtimeSettings.resolvedURL != nil else {
            updateConnectionStatus(.unconfigured)
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
            return
        }
        if let room = savedRoom, shouldAutoConnect {
            connect(to: room)
        } else {
            updateConnectionStatus(.disconnected)
        }
    }

    // MARK: - Connection

    private func connect(to room: String) {
        UserDefaults.standard.set(room, forKey: DefaultsKey.room)
        UserDefaults.standard.set(true, forKey: DefaultsKey.autoConnect)
        updateRoomMenuItem(room)
        settingsController?.update(room: room)
        socket.connect(room: room)
    }

    /// Stops the socket but keeps the room, so rejoining is one click.
    private func disconnect() {
        socket.disconnect()
        UserDefaults.standard.set(false, forKey: DefaultsKey.autoConnect)
    }

    // MARK: - Menu state

    @objc private func openSettings() {
        settingsController.present(
            room: savedRoom,
            overlayVisible: overlayController.isVisible,
            connection: connectionState
        )
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

    private func updateRoomMenuItem(_ room: String?) {
        roomMenuItem?.title = room.map { "Room: \($0)" } ?? "Room: None selected"
    }

    private func updateConnectionStatus(_ state: ReactionConnectionState) {
        connectionState = state
        switch state {
        case .connecting: connectionMenuItem?.title = "Connection: Connecting…"
        case .connected: connectionMenuItem?.title = "Connection: Connected"
        case .reconnecting: connectionMenuItem?.title = "Connection: Reconnecting…"
        case .disconnected: connectionMenuItem?.title = "Connection: Disconnected"
        case .unconfigured: connectionMenuItem?.title = "Connection: No server configured"
        }
        settingsController?.update(connection: state)
        updateStatusIcon(active: overlayController.isVisible)
    }

    // MARK: - Overlay

    @objc private func toggleOverlay() {
        setOverlay(visible: !overlayController.isVisible)
    }

    private func setOverlay(visible: Bool) {
        guard overlayController.isVisible != visible else { return }
        overlayController.toggle()

        let active = overlayController.isVisible
        updateStatusIcon(active: active)
        statusMenuItem.title = active ? "Status: Active" : "Status: Paused"
        toggleMenuItem.title = active ? "Hide Overlay" : "Show Overlay"
        settingsController?.update(overlayVisible: active)
    }

    @objc private func toggleLeaderboard() {
        leaderboardController.toggle()
        leaderboardToggleMenuItem.title = leaderboardController.isVisible ? "Hide Leaderboard" : "Show Leaderboard"
    }

    private func updateStatusIcon(active: Bool) {
        let color: NSColor
        switch connectionState {
        case .connected: color = .systemGreen
        case .connecting, .reconnecting: color = .systemOrange
        case .disconnected: color = .systemRed
        case .unconfigured: color = .systemGray
        }
        statusItem.button?.image = nil
        statusItem.button?.attributedTitle = NSAttributedString(
            string: "\(active ? "●" : "○") 🥜",
            attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 14)]
        )
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
