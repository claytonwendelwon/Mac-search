import Foundation

/// Minimal file logger so we can diagnose startup/hotkey behavior even when
/// the app is launched as a bundle (where stdout/stderr go nowhere).
/// Writes to ~/Library/Logs/Beacon.log.
enum Log {
    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        return dir.appendingPathComponent("Beacon.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        print(message) // also to stdout when run directly
        guard let data = line.data(using: .utf8) else { return }

        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        // Use the throwing FileHandle APIs so any failure surfaces as a Swift
        // error instead of an Objective-C exception (which AppKit would
        // silently swallow during launch).
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Best-effort logging only; never let logging break startup.
        }
    }
}
