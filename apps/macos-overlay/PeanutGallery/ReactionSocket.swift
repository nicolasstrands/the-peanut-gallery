import Foundation

struct ReactionMessage: Decodable {
    let type: String
    let emoji: String?
}

final class ReactionSocket {
    private var task: URLSessionWebSocketTask?
    private let onReaction: (String) -> Void
    private let session: URLSession

    init(onReaction: @escaping (String) -> Void) {
        self.onReaction = onReaction
        self.session = URLSession(configuration: .default)
    }

    func connect(room: String) {
        task?.cancel(with: .goingAway, reason: nil)
        guard let url = URL(string: "wss://gallerybutter.arcodelabs.com/rooms/\(room)") else { return }
        task = session.webSocketTask(with: url)
        task?.resume()
        listen()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            if case .success(.string(let text)) = result,
               let data = text.data(using: .utf8),
               let message = try? JSONDecoder().decode(ReactionMessage.self, from: data),
               message.type == "reaction", let emoji = message.emoji {
                self.onReaction(emoji)
            }
            self.listen()
        }
    }
}
