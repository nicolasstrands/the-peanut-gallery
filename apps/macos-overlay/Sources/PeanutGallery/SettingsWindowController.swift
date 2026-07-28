import AppKit

/// Every user-configurable value in one window, in place of the stack of
/// single-purpose alerts the menu used to put up.
///
/// The Save action validates and applies server/room together so connection
/// updates can happen in one controlled step.
final class SettingsWindowController: NSWindowController {
    /// Called with a normalized room code, a normalized server URL, and a web UI URL.
    var onSaveChanges: ((_ room: String, _ server: String?, _ webURL: String?) -> Void)?
    var onOverlayVisibilityChange: ((Bool) -> Void)?

    private let serverField = NSTextField()
    private let serverNote = NSTextField(labelWithString: "")
    private let roomField = NSTextField()
    private let roomNote = NSTextField(labelWithString: "")
    private let webURLField = NSTextField()
    private let webURLNote = NSTextField(labelWithString: "")
    private let overlayCheckbox = NSButton(checkboxWithTitle: "Show reactions on screen", target: nil, action: nil)
    private let connectionLabel = NSTextField(labelWithString: "Disconnected")
    private let primaryButton = NSButton(title: "Save Changes", target: nil, action: nil)

    /// Notes sit in their own grid rows so they can collapse when empty;
    /// otherwise the blank rows leave uneven gaps between the fields.
    private var serverNoteRow: NSGridRow?
    private var roomNoteRow: NSGridRow?
    private var webURLNoteRow: NSGridRow?

    private var connection: ReactionConnectionState = .disconnected
    private var hasBeenPositioned = false

    private static let fieldWidth: CGFloat = 340

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Peanut Gallery Settings"
        // Closing an NSWindow deallocates it by default, which would crash the
        // second time the menu opens Settings.
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        buildLayout()
    }

    // MARK: - Layout

    private func buildLayout() {
        guard let contentView = window?.contentView else { return }

        configure(serverField, placeholder: "wss://peanut-gallery-realtime.<subdomain>.workers.dev", width: Self.fieldWidth)
        configure(roomField, placeholder: "e.g. ABC123", width: 160)
        configure(webURLField, placeholder: "https://peanutgallery.arcodelabs.com", width: Self.fieldWidth)
        // Return in a field acts on that field rather than firing the window's
        // default button, so Return on the server just normalizes/validates it.
        serverField.target = self
        serverField.action = #selector(validateServerAction)
        roomField.target = self
        roomField.action = #selector(primaryTapped)
        webURLField.target = self
        webURLField.action = #selector(primaryTapped)

        for note in [serverNote, roomNote, webURLNote] {
            note.font = .systemFont(ofSize: 11)
            note.textColor = .secondaryLabelColor
            note.lineBreakMode = .byWordWrapping
            note.maximumNumberOfLines = 2
            note.preferredMaxLayoutWidth = Self.fieldWidth
            note.translatesAutoresizingMaskIntoConstraints = false
            note.widthAnchor.constraint(equalToConstant: Self.fieldWidth).isActive = true
        }
        connectionLabel.textColor = .secondaryLabelColor

        overlayCheckbox.target = self
        overlayCheckbox.action = #selector(overlayToggled)

        let grid = NSGridView(views: [
            [Self.label("Realtime server"), serverField],
            [NSGridCell.emptyContentView, serverNote],
            [Self.label("Room code"), roomField],
            [NSGridCell.emptyContentView, roomNote],
            [Self.label("Web UI URL"), webURLField],
            [NSGridCell.emptyContentView, webURLNote],
            [Self.label("Overlay"), overlayCheckbox],
            [Self.label("Connection"), connectionLabel],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        serverNoteRow = grid.row(at: 1)
        roomNoteRow = grid.row(at: 3)
        webURLNoteRow = grid.row(at: 5)
        serverNoteRow?.isHidden = true
        roomNoteRow?.isHidden = true
        webURLNoteRow?.isHidden = true

        primaryButton.target = self
        primaryButton.action = #selector(primaryTapped)
        primaryButton.bezelStyle = .rounded
        primaryButton.keyEquivalent = "\r"

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeTapped))
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\u{1b}"

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let buttons = NSStackView(views: [spacer, closeButton, primaryButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(grid)
        contentView.addSubview(buttons)

        // Pinning the buttons directly below the grid lets the content view's
        // fitting size drive the window height, so a collapsing note row closes
        // the gap instead of leaving a hole in the middle.
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),

            buttons.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 24),
            buttons.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
        ])
    }

    /// An NSTextField wraps long text onto a second line that its single-line
    /// height then clips. Scrolling instead keeps a full URL readable.
    private func configure(_ field: NSTextField, placeholder: String, width: CGFloat) {
        field.placeholderString = placeholder
        field.delegate = self
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byClipping
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    private static func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    private func resizeToFit() {
        guard let window, let contentView = window.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        let size = contentView.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        window.setContentSize(size)
    }

    // MARK: - Presenting

    func present(room: String?, overlayVisible: Bool, connection: ReactionConnectionState, webURL: String?) {
        let environmentControlled = RealtimeSettings.isOverriddenByEnvironment
        serverField.isEditable = !environmentControlled
        serverField.stringValue = (environmentControlled ? RealtimeSettings.resolvedURL : RealtimeSettings.storedURL) ?? ""
        setNote(serverNote, row: serverNoteRow, environmentControlled
            ? "Set by PEANUT_GALLERY_REALTIME_URL. Unset it and relaunch to edit this."
            : "")

        roomField.stringValue = room ?? Self.roomOnPasteboard() ?? ""
        setNote(roomNote, row: roomNoteRow, "")
        webURLField.stringValue = webURL ?? ""
        setNote(webURLNote, row: webURLNoteRow, "Leave blank to use https://peanutgallery.arcodelabs.com.")
        overlayCheckbox.state = overlayVisible ? .on : .off
        update(connection: connection)

        resizeToFit()
        // An accessory app never comes forward on its own, so without this the
        // window opens behind whatever the user was looking at.
        NSApp.activate(ignoringOtherApps: true)
        if !hasBeenPositioned {
            window?.center()
            hasBeenPositioned = true
        }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(environmentControlled ? roomField : serverField)
    }

    func update(connection state: ReactionConnectionState) {
        connection = state
        switch state {
        case .connecting: connectionLabel.stringValue = "Connecting…"
        case .connected: connectionLabel.stringValue = "Connected"
        case .reconnecting: connectionLabel.stringValue = "Reconnecting…"
        case .disconnected: connectionLabel.stringValue = "Disconnected"
        case .unconfigured: connectionLabel.stringValue = "No server configured"
        }
        refreshPrimaryButton()
    }

    func update(room: String?) {
        roomField.stringValue = room ?? ""
        refreshPrimaryButton()
    }

    func update(overlayVisible: Bool) {
        overlayCheckbox.state = overlayVisible ? .on : .off
    }

    /// The one action button, always named for what it is about to do.
    private func refreshPrimaryButton() {
        let hasRoom = !roomField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasServer = RealtimeSettings.isOverriddenByEnvironment
            || !serverField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        primaryButton.title = "Save Changes"
        primaryButton.isEnabled = hasRoom && hasServer
    }

    private func setNote(_ field: NSTextField, row: NSGridRow?, _ text: String, isError: Bool = false) {
        field.stringValue = text
        field.textColor = isError ? .systemRed : .secondaryLabelColor
        row?.isHidden = text.isEmpty
    }

    private func reject(_ note: NSTextField, row: NSGridRow?, _ message: String, focus: NSTextField) {
        setNote(note, row: row, message, isError: true)
        resizeToFit()
        window?.makeFirstResponder(focus)
    }

    /// Room codes travel by copy and paste, so offer the clipboard when there is
    /// no room to show. Six alphanumerics is what the web deck generates.
    private static func roomOnPasteboard() -> String? {
        guard let clipboard = NSPasteboard.general.string(forType: .string) else { return nil }
        let candidate = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.count == 6,
              candidate.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
        else { return nil }
        return candidate.uppercased()
    }

    // MARK: - Actions

    /// Normalizes and validates the server field.
    /// Returns nil when no editable server is available.
    @discardableResult
    private func validatedServerInput(showError: Bool) -> String? {
        guard !RealtimeSettings.isOverriddenByEnvironment else { return nil }

        let raw = serverField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            if showError {
                setNote(serverNote, row: serverNoteRow, "Enter the address of your realtime Worker first.", isError: true)
            } else {
                setNote(serverNote, row: serverNoteRow, "")
            }
            resizeToFit()
            return nil
        }
        guard let address = RealtimeSettings.normalized(raw) else {
            if showError {
                setNote(serverNote, row: serverNoteRow, "Not a usable address. Try wss://your-worker.example.workers.dev or ws://localhost:8787.", isError: true)
            }
            resizeToFit()
            return nil
        }

        serverField.stringValue = address
        setNote(serverNote, row: serverNoteRow, "")
        resizeToFit()
        return address
    }

    @objc private func validateServerAction() {
        _ = validatedServerInput(showError: false)
    }

    @objc private func overlayToggled() {
        onOverlayVisibilityChange?(overlayCheckbox.state == .on)
    }

    @objc private func primaryTapped() {
        let normalizedServer = validatedServerInput(showError: true)
        if !RealtimeSettings.isOverriddenByEnvironment, normalizedServer == nil {
            window?.makeFirstResponder(serverField)
            return
        }

        guard let room = RoomCode.normalized(roomField.stringValue) else {
            reject(roomNote, row: roomNoteRow, "Use 3–64 letters, numbers, hyphens, or underscores.", focus: roomField)
            return
        }

        roomField.stringValue = room
        setNote(roomNote, row: roomNoteRow, "")
        resizeToFit()
        let webURL = webURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        onSaveChanges?(room, normalizedServer, webURL.isEmpty ? nil : webURL)
    }

    @objc private func closeTapped() {
        window?.performClose(nil)
    }
}

// MARK: - NSTextFieldDelegate

extension SettingsWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        guard field === roomField || field === serverField || field === webURLField else { return }
        refreshPrimaryButton()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === serverField else { return }
        _ = validatedServerInput(showError: false)
        refreshPrimaryButton()
    }
}

// MARK: - NSWindowDelegate

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Giving up first responder ends editing, which commits a server the
        // user typed and then closed the window without tabbing out of.
        window?.makeFirstResponder(nil)
    }
}
