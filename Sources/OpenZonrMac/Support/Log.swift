import Foundation

/// Timestamped, prefixed output for `watch`.
///
/// The log *is* the deliverable of the tracer bullet — it answers whether the
/// retry policy holds against real applications — so it gets a deliberate
/// format rather than scattered `print` calls.
///
/// It has a second audience now. In the menu bar app there is no terminal to
/// read, so every entry is additionally handed to registered observers. That is
/// why an entry is a value with a level rather than a pre-rendered string: the
/// app wants to filter and colour them, the terminal wants one line.
public enum Log {

    /// How loud an entry is, and what it means.
    public enum Level: String, Sendable, CaseIterable {
        /// Progress of the run itself.
        case info
        /// Supporting detail for the entry above it.
        case detail
        /// Something happened in the observed system — a window appeared.
        case event
        /// A window ended up where it was supposed to.
        case success
        /// Something did not work, or worked in a way worth questioning.
        case warn

        /// The marker used in the terminal.
        public var marker: String {
            switch self {
            case .info: return "·"
            case .detail: return " "
            case .event: return "▸"
            case .success: return "✓"
            case .warn: return "!"
            }
        }
    }

    /// One log line, as a value.
    public struct Entry: Sendable, Identifiable, Hashable {
        public let id: UUID
        public let date: Date
        public let level: Level
        public let message: String

        public init(id: UUID = UUID(), date: Date = Date(), level: Level, message: String) {
            self.id = id
            self.date = date
            self.level = level
            self.message = message
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    // The log is written from the main actor in practice, but it is reached
    // through free functions from every layer, so the state is guarded rather
    // than isolated. A lock is honest about that; `@MainActor` would only push
    // the problem into the callers.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var observers: [UUID: @Sendable (Entry) -> Void] = [:]
    nonisolated(unsafe) private static var echoes = true

    /// Whether entries are still printed to standard output.
    ///
    /// The app leaves this on: when it is started from a terminal for debugging,
    /// the familiar log is exactly what one wants to see.
    public static var echoesToStandardOutput: Bool {
        get { lock.withLock { echoes } }
        set { lock.withLock { echoes = newValue } }
    }

    /// Registers a sink for every entry from now on. Returns a removal token.
    ///
    /// The closure runs on whatever thread produced the entry; an observer that
    /// touches UI has to hop to the main actor itself.
    @discardableResult
    public static func addObserver(_ observer: @escaping @Sendable (Entry) -> Void) -> UUID {
        let token = UUID()
        lock.withLock { observers[token] = observer }
        return token
    }

    public static func removeObserver(_ token: UUID) {
        _ = lock.withLock { observers.removeValue(forKey: token) }
    }

    public static func info(_ message: String) { emit(.info, message) }
    public static func detail(_ message: String) { emit(.detail, message) }
    public static func event(_ message: String) { emit(.event, message) }
    public static func success(_ message: String) { emit(.success, message) }
    public static func warn(_ message: String) { emit(.warn, message) }

    private static func emit(_ level: Level, _ message: String) {
        let entry = Entry(level: level, message: message)
        let (shouldEcho, sinks) = lock.withLock { (echoes, Array(observers.values)) }

        if shouldEcho {
            let stamp = formatter.string(from: entry.date)
            let lines = message.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                let prefix = index == 0 ? "\(stamp) \(level.marker) " : String(repeating: " ", count: 15)
                print(prefix + line)
            }
            fflush(stdout)
        }

        for sink in sinks { sink(entry) }
    }
}

/// An error with a message that is already meant for the user.
public struct CommandError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}
