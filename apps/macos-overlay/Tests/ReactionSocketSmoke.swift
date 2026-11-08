// Run against `pnpm dev:realtime`; see README for the compile command.
// Uses an injected recorder, so this test never writes to the user's Keychain.
import Foundation

private struct CreatedRoom: Decodable {
    let roomId: String
    let displayToken: String
}

private final class Observations: @unchecked Sendable {
    private let lock = NSLock()
    private var status = ""
    private var tokens: [String] = []
    func update(_ state: ReactionConnectionState) {
        lock.lock(); defer { lock.unlock() }
        switch state {
        case .connected: status = "connected"
        case .accessDenied: status = "denied"
        default: status = "waiting"
        }
    }
    func accepted(_ token: String) { lock.lock(); defer { lock.unlock() }; tokens.append(token) }
    func snapshot() -> (String, [String]) { lock.lock(); defer { lock.unlock() }; return (status, tokens) }
}

@main
private struct ReactionSocketSmoke {
    static func main() async throws {
        let origin = "http://127.0.0.1:8787"
        setenv("PEANUT_GALLERY_REALTIME_URL", "ws://127.0.0.1:8787", 1)
        var request = URLRequest(url: URL(string: "\(origin)/rooms")!)
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 201 else { fatalError("Start the local realtime Worker first") }
        let room = try JSONDecoder().decode(CreatedRoom.self, from: data)
        let observed = Observations()
        let socket = ReactionSocket(
            onReaction: { _ in }, onLeaderboard: { _ in }, onPollState: { _ in },
            onStateChange: { observed.update($0) },
            onDisplayAuthorized: { token, _, _ in observed.accepted(token) }
        )
        socket.connect(room: room.roomId, displayToken: room.displayToken)
        try await wait { observed.snapshot().0 == "connected" }
        precondition(observed.snapshot().1 == [room.displayToken], "Valid credential was not accepted")
        socket.connect(room: room.roomId, displayToken: String(repeating: "0", count: 64))
        try await wait { observed.snapshot().0 == "denied" }
        precondition(observed.snapshot().1 == [room.displayToken], "Rejected credential replaced a working one")
        socket.connect(room: room.roomId, displayToken: room.displayToken)
        try await wait { observed.snapshot().0 == "connected" && observed.snapshot().1.count == 2 }
        socket.connect(room: room.roomId, displayToken: String(repeating: "0", count: 64))
        socket.connect(room: room.roomId, displayToken: room.displayToken)
        try await wait { observed.snapshot().0 == "connected" && observed.snapshot().1.count == 3 }
        precondition(observed.snapshot().1.allSatisfy { $0 == room.displayToken }, "Stale handshake authorized another connection's credential")
        socket.disconnect()
        print("PASS: native display authorization, rejection without persistence, and recovery")
    }

    private static func wait(until predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !predicate() {
            guard Date() < deadline else { fatalError("Native authorization timed out") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
