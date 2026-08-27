import Foundation

/// Timestamped, prefixed output for `watch`.
///
/// The log *is* the deliverable of the tracer bullet — it answers whether the
/// retry policy holds against real applications — so it gets a deliberate
/// format rather than scattered `print` calls.
enum Log {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func info(_ message: String) { emit("·", message) }
    static func detail(_ message: String) { emit(" ", message) }
    static func event(_ message: String) { emit("▸", message) }
    static func success(_ message: String) { emit("✓", message) }
    static func warn(_ message: String) { emit("!", message) }

    private static func emit(_ marker: String, _ message: String) {
        let stamp = formatter.string(from: Date())
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            let prefix = index == 0 ? "\(stamp) \(marker) " : String(repeating: " ", count: 15)
            print(prefix + line)
        }
        fflush(stdout)
    }
}

/// An error with a message that is already meant for the user.
struct CommandError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
