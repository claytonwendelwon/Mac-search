import AppKit
import UniformTypeIdentifiers

/// File-system operations invoked from the result context menu (and, later,
/// bulk actions). Every method operates on real files; callers gate on
/// `source == .file`. Destructive operations are limited to Move to Trash,
/// which is reversible.
enum FileActions {
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Apps capable of opening the file, for the "Open With" submenu.
    static func applications(toOpen url: URL) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: url)
    }

    static func open(_ url: URL, withApplicationAt appURL: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    /// The "Other…" path: pick any app via the standard open panel.
    static func openWithOtherApp(_ url: URL) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Open"
        if panel.runModal() == .OK, let appURL = panel.url {
            open(url, withApplicationAt: appURL)
        }
    }

    /// Move files to the Trash (reversible). Per-item so one failure doesn't
    /// abort the rest.
    static func moveToTrash(_ urls: [URL]) {
        for url in urls {
            NSWorkspace.shared.recycle([url], completionHandler: nil)
        }
    }

    /// Finder-style duplicate: "name copy.ext", then " copy 2", " copy 3", …
    @discardableResult
    static func duplicate(_ url: URL) -> URL? {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        func candidate(_ n: Int) -> URL {
            let suffix = n == 1 ? " copy" : " copy \(n)"
            let name = ext.isEmpty ? base + suffix : "\(base)\(suffix).\(ext)"
            return dir.appendingPathComponent(name)
        }
        var n = 1
        var dest = candidate(n)
        while fm.fileExists(atPath: dest.path) { n += 1; dest = candidate(n) }
        do {
            try fm.copyItem(at: url, to: dest)
            return dest
        } catch {
            Log.write("duplicate failed: \(error)")
            return nil
        }
    }

    /// Rename in place. Returns the new URL on success, nil on invalid name or
    /// failure (e.g. name collision).
    @discardableResult
    static func rename(_ url: URL, to newName: String) -> URL? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else { return nil }
        let dest = url.deletingLastPathComponent().appendingPathComponent(trimmed)
        guard dest.path != url.path else { return url }
        guard !FileManager.default.fileExists(atPath: dest.path) else { return nil }
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            return dest
        } catch {
            Log.write("rename failed: \(error)")
            return nil
        }
    }

    /// Compress to a .zip beside the original — a compressed *copy*, exactly how
    /// Finder's Compress works (ditto keeps the parent folder + resource forks).
    /// Runs off the main thread; on success the new archive is revealed in
    /// Finder so the user sees it landed. Large items can take a while.
    static func compress(_ url: URL) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        func candidate(_ n: Int) -> URL {
            let name = n == 0 ? "\(base).zip" : "\(base) \(n).zip"
            return dir.appendingPathComponent(name)
        }
        var n = 0
        var dest = candidate(n)
        while fm.fileExists(atPath: dest.path) { n += 1; dest = candidate(n) }
        let finalDest = dest
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            proc.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent",
                              url.path, finalDest.path]
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {
                Log.write("compress failed: \(error)")
            }
            let ok = proc.terminationStatus == 0 && fm.fileExists(atPath: finalDest.path)
            if ok {
                DispatchQueue.main.async {
                    NSWorkspace.shared.activateFileViewerSelecting([finalDest])
                }
            } else {
                Log.write("compress: no archive produced for \(url.path) (status \(proc.terminationStatus))")
            }
        }
    }

    /// Show the Finder "Get Info" window for the file.
    static func getInfo(_ url: URL) {
        let escaped = url.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Finder"
          activate
          open information window of (POSIX file "\(escaped)" as alias)
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&err)
            if let err { Log.write("getInfo AppleScript error: \(err)") }
        }
    }

    /// Display name for an app URL, without the ".app" suffix.
    static func appDisplayName(_ appURL: URL) -> String {
        let name = FileManager.default.displayName(atPath: appURL.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
