import Foundation

enum ReactionConnectionState {
    case disconnected
    case connecting
    case connected
    case reconnecting
    /// No realtime server has been configured yet, so there is nothing to dial.
    case unconfigured
    case accessDenied

    /// A socket is open or on its way up. Drives whether the UI offers to
    /// connect or to disconnect.
    var isLive: Bool {
        switch self {
        case .connected, .connecting, .reconnecting: return true
        case .disconnected, .unconfigured, .accessDenied: return false
        }
    }
}

struct ReactionMessage: Decodable {
    let type: String
    let emoji: String?
    let counts: [String: Int]?
}

struct PollOption: Decodable {
    let id: String
    let label: String
}

struct PollState: Decodable {
    let id: String
    let question: String
    let options: [PollOption]
    let startAt: Int64
    let endAt: Int64
    let status: String
    let tally: [String: Int]?
}

private struct RoomStatusMessage: Decodable {
    let type: String
    let code: String?
}

struct PollStateMessage: Decodable {
    let type: String
    let poll: PollState?
}

final class ReactionSocket {
    private var task: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var reconnectWorkItem: DispatchWorkItem?
    private var displayToken: String?
    private var room: String?
    private var reconnectAttempt = 0
    private var stopping = false

    private let onReaction: (String) -> Void
    private let onLeaderboard: ([String: Int]) -> Void
    private let onPollState: (PollState?) -> Void
    private let onStateChange: (ReactionConnectionState) -> Void
    private let session = URLSession(configuration: .default)
    private let onDisplayAuthorized: (String, String, String) -> Void

    init(
        onReaction: @escaping (String) -> Void,
        onLeaderboard: @escaping ([String: Int]) -> Void,
        onPollState: @escaping (PollState?) -> Void,
        onStateChange: @escaping (ReactionConnectionState) -> Void,
        onDisplayAuthorized: @escaping (String, String, String) -> Void = { token, room, server in
            DisplayCredentialStore.save(token, room: room, server: server)
        }
    ) {
        self.onReaction = onReaction
        self.onLeaderboard = onLeaderboard
        self.onPollState = onPollState
        self.onStateChange = onStateChange
        self.onDisplayAuthorized = onDisplayAuthorized
    }

    func connect(room: String, displayToken: String? = nil) {
        self.displayToken = displayToken
        self.room = room
        stopping = false
        reconnectAttempt = 0
        reconnectWorkItem?.cancel()
        openConnection()
    }

    func disconnect() {
        stopping = true
        room = nil
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        stopPingTimer()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        notify(.disconnected)
    }

    private func openConnection() {
        guard !stopping, let room else { return }
        stopPingTimer()
        task?.cancel(with: .goingAway, reason: nil)

        // Nothing to dial until a server is configured. Retrying on a timer would
        // only burn cycles: saving a server calls connect(room:) again.
        guard let base = RealtimeSettings.resolvedURL else {
            notify(.unconfigured)
            return
        }

        notify(reconnectAttempt == 0 ? .connecting : .reconnecting)

        guard let url = URL(string: "\(base)/rooms/\(room)") else {
            scheduleReconnect()
            return
        }

        let connection = session.webSocketTask(with: url)
        task = connection
        connection.resume()
        let credential = displayToken
        sendJoinMessage(room: room, displayToken: credential, on: connection)
        startPingTimer(for: connection)
        listen(on: connection, room: room, displayToken: credential, endpoint: base)
    }

    private func sendJoinMessage(room: String, displayToken: String?, on connection: URLSessionWebSocketTask) {
        var payload: [String: String] = [
            "type": "join-room",
            "roomId": room,
            "clientType": "macos"
        ]
        if let displayToken { payload["displayToken"] = displayToken }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        connection.send(.string(text)) { [weak self, weak connection] error in
            guard let self, let connection, self.task === connection, error != nil else { return }
            self.connectionDidEnd(connection)
        }
    }

    private func listen(on connection: URLSessionWebSocketTask, room: String, displayToken: String?, endpoint: String) {
        connection.receive { [weak self, weak connection] result in
            guard let self, let connection else { return }
            guard self.task === connection else { return }

            switch result {
            case .success(.string(let text)):
                if let data = text.data(using: .utf8),
                   let status = try? JSONDecoder().decode(RoomStatusMessage.self, from: data) {
                    if status.type == "room-ready" {
                        // Bind acceptance to the immutable connection inputs,
                        // and recheck identity on the queue that mutates sessions.
                        DispatchQueue.main.async { [weak self, weak connection] in
                            guard let self, let connection, self.task === connection else { return }
                            if let displayToken { self.onDisplayAuthorized(displayToken, room, endpoint) }
                            self.reconnectAttempt = 0
                            self.onStateChange(.connected)
                        }
                    } else if status.type == "protocol-error",
                              status.code == "unauthorized" || status.code == "room_expired" || status.code == "invalid_room" {
                        DispatchQueue.main.async { [weak self, weak connection] in
                            guard let self, let connection, self.task === connection else { return }
                            self.stopping = true
                            self.stopPingTimer()
                            self.task = nil
                            connection.cancel(with: .policyViolation, reason: nil)
                            self.onStateChange(.accessDenied)
                        }
                        return
                    }
                }
                if let data = text.data(using: .utf8),
                   let message = try? JSONDecoder().decode(ReactionMessage.self, from: data),
                   message.type == "reaction", let emoji = message.emoji {
                    self.onReaction(emoji)
                }
                if let data = text.data(using: .utf8),
                   let message = try? JSONDecoder().decode(ReactionMessage.self, from: data),
                   message.type == "leaderboard", let counts = message.counts {
                    self.onLeaderboard(counts)
                }
                if let data = text.data(using: .utf8),
                   let message = try? JSONDecoder().decode(PollStateMessage.self, from: data),
                   message.type == "poll-state" {
                    self.onPollState(message.poll)
                }
                self.listen(on: connection, room: room, displayToken: displayToken, endpoint: endpoint)
            case .success(.data):
                self.listen(on: connection, room: room, displayToken: displayToken, endpoint: endpoint)
            case .failure:
                self.connectionDidEnd(connection)
            @unknown default:
                self.connectionDidEnd(connection)
            }
        }
    }

    private func connectionDidEnd(_ connection: URLSessionWebSocketTask) {
        guard task === connection else { return }
        task = nil
        stopPingTimer()
        if !stopping { scheduleReconnect() }
        else { notify(.disconnected) }
    }

    private func scheduleReconnect() {
        guard !stopping, room != nil, reconnectWorkItem == nil else { return }
        notify(.reconnecting)
        let delay = min(pow(2.0, Double(reconnectAttempt)), 30.0)
        reconnectAttempt += 1
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWorkItem = nil
            self.openConnection()
        }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startPingTimer(for connection: URLSessionWebSocketTask) {
        connection.sendPing { [weak self, weak connection] error in
            guard let self, let connection, self.task === connection else { return }
            if error != nil {
                self.connectionDidEnd(connection)
            }
        }

        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self, weak connection] _ in
            guard let self, let connection, self.task === connection else { return }
            connection.sendPing { [weak self] error in
                if error != nil { self?.connectionDidEnd(connection) }
            }
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func notify(_ state: ReactionConnectionState) {
        DispatchQueue.main.async { [onStateChange] in onStateChange(state) }
    }
}
