import Foundation

/// A room code is the short token the host shares from the web deck. It names
/// one Durable Object, and the Worker treats it case-sensitively, so codes are
/// upper-cased on the way in to match what the deck generates.
enum RoomCode {
    private static let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

    /// Trims and upper-cases `raw`, returning nil when the result could not be
    /// a room code.
    static func normalized(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (3...64).contains(code.count),
              code.unicodeScalars.allSatisfy(allowed.contains)
        else { return nil }
        return code
    }
}
