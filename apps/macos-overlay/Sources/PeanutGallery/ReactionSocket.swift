import Foundation

enum ReactionConnectionState {
    case disconnected
    case connecting
    case connected
    case reconnecting
    /// No realtime server has been configured yet, so there is nothing to dial.
    case unconfigured
}

struct ReactionMessage: Decodable { let type: String; let emoji: String? }

final class ReactionSocket {
    private var task: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var reconnectWorkItem: DispatchWorkItem?
    private var room: String?
    private var reconnectAttempt = 0
    private var stopping = false

    private let onReaction: (String) -> Void
    private let onStateChange: (ReactionConnectionState) -> Void
    private let session = URLSession(configuration: .default)

    init(onReaction: @escaping (String) -> Void, onStateChange: @escaping (ReactionConnectionState) -> Void) {
        self.onReaction = onReaction
        self.onStateChange = onStateChange
    }

    func connect(room: String) {
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
        startPingTimer(for: connection)
        listen(on: connection)
    }

    private func listen(on connection: URLSessionWebSocketTask) {
        connection.receive { [weak self, weak connection] result in
            guard let self, let connection else { return }
            guard self.task === connection else { return }

            switch result {
            case .success(.string(let text)):
                if let data = text.data(using: .utf8),
                   let message = try? JSONDecoder().decode(ReactionMessage.self, from: data),
                   message.type == "reaction", let emoji = message.emoji {
                    self.onReaction(emoji)
                }
                self.listen(on: connection)
            case .success(.data):
                self.listen(on: connection)
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
            } else {
                self.reconnectAttempt = 0
                self.notify(.connected)
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
