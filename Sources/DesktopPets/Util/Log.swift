import Foundation
import os

/// Logging, plus the one place that reports an unrecoverable startup failure.
enum Log {
    private static let subsystem = "com.desktoppets.DesktopPets"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let sprite = Logger(subsystem: subsystem, category: "sprite")
    static let window = Logger(subsystem: subsystem, category: "window")

    /// Writes to stderr as well as the unified log, so `swift run` in a terminal shows the
    /// reason immediately instead of only in Console.app.
    static func error(_ message: String) {
        FileHandle.standardError.write(Data("DesktopPets: \(message)\n".utf8))
        app.error("\(message, privacy: .public)")
    }

    static func warning(_ message: String) {
        app.warning("\(message, privacy: .public)")
    }

    static func info(_ message: String) {
        app.info("\(message, privacy: .public)")
    }
}
