import Foundation

struct AppRecord {
    let path: String
    let name: String
    let bundleIdentifier: String?
    let modified: Date?
    let foldedName: String
}

/// Direct scanner for installed `.app` bundles. Spotlight often misses
/// third-party apps or apps installed outside /System/Applications; this keeps
/// the Apps filter launcher-like and predictable.
final class AppStore {
    private let fm = FileManager.default
    private let home = NSHomeDirectory()
    private var cache: [AppRecord]?

    func search(tokens: [String], limit: Int = 120,
                isCancelled: (() -> Bool)? = nil) -> [AppRecord] {
        let apps = loadApps(isCancelled: isCancelled)
        guard !tokens.isEmpty else { return Array(apps.prefix(limit)) }

        return apps
            .filter { app in tokens.allSatisfy { app.foldedName.contains($0) } }
            .sorted { a, b in
                let sa = score(a, tokens: tokens)
                let sb = score(b, tokens: tokens)
                if sa != sb { return sa < sb }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    func refresh() {
        cache = nil
    }

    private func loadApps(isCancelled: (() -> Bool)?) -> [AppRecord] {
        if let cache { return cache }
        var byPath: [String: AppRecord] = [:]
        var visited = 0

        for root in roots() {
            guard isCancelled?() != true else { return [] }
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                visited += 1
                if visited & 0xFF == 0, isCancelled?() == true { return [] }
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                let path = url.path
                guard byPath[path] == nil else { continue }
                byPath[path] = appRecord(at: url)
            }
        }

        let apps = byPath.values
            .sorted {
                let aSystem = isSystemApp($0.path), bSystem = isSystemApp($1.path)
                if aSystem != bSystem { return !aSystem } // third-party/user apps first
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        cache = apps
        Log.write("AppStore: loaded \(apps.count) apps")
        return apps
    }

    private func appRecord(at url: URL) -> AppRecord {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: plistURL) as? [String: Any]
        let displayName = info?["CFBundleDisplayName"] as? String
        let bundleName = info?["CFBundleName"] as? String
        let bundleIdentifier = info?["CFBundleIdentifier"] as? String
        let name = displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return AppRecord(path: url.path,
                         name: name,
                         bundleIdentifier: bundleIdentifier,
                         modified: modified,
                         foldedName: name.searchFolded)
    }

    private func roots() -> [URL] {
        [
            "/Applications",
            home + "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/Applications/Setapp",
            home + "/Applications/Setapp"
        ]
            .filter { fm.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func score(_ app: AppRecord, tokens: [String]) -> Int {
        let query = tokens.joined(separator: " ")
        if app.foldedName == query { return 0 }
        if app.foldedName.hasPrefix(query) { return 50 }
        if tokens.allSatisfy({ SearchText.hasWordStart(app.foldedName, $0) }) { return 100 }
        return 200
    }

    private func isSystemApp(_ path: String) -> Bool {
        path.hasPrefix("/System/")
    }
}
