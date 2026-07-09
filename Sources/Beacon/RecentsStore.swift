import Foundation
import UniformTypeIdentifiers

/// A file discovered by Beacon's filesystem-backed Recents scanner.
struct RecentFileRecord {
    let path: String
    let name: String
    let kind: String
    let size: Int64?
    let modified: Date?
    let dateAdded: Date?
    let isFolder: Bool
    let isApp: Bool
    let recency: Date
    let matchQuality: SearchText.MatchQuality
}

/// A deterministic Recents backend that does not rely on Spotlight/Finder's
/// "recents" behavior. Spotlight can lag or miss freshly saved/downloaded
/// files; the filesystem does not. We scan visible user folders, ignore app
/// internals, and sort by the newest touch we can observe.
final class RecentsStore {
    private let home = NSHomeDirectory()
    private let fm = FileManager.default
    private let windowDays = 30.0
    private let maxVisitedFiles = 250_000

    private let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isPackageKey,
        .contentModificationDateKey,
        .creationDateKey,
        .addedToDirectoryDateKey,
        .fileSizeKey,
        .contentTypeKey
    ]

    func search(tokens: [String], limit: Int = 200,
                isCancelled: (() -> Bool)? = nil) -> [RecentFileRecord] {
        let cutoff = Date(timeIntervalSinceNow: -windowDays * 86_400)
        var visited = 0
        var out: [RecentFileRecord] = []
        out.reserveCapacity(limit * 2)

        for root in roots() {
            guard isCancelled?() != true else { return [] }
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, error in
                    Log.write("RecentsStore: skip \(url.path) err=\(error.localizedDescription)")
                    return true
                }
            ) else { continue }

            for case let url as URL in enumerator {
                visited += 1
                if visited & 0x3FF == 0, isCancelled?() == true { return [] }
                if visited > maxVisitedFiles {
                    Log.write("RecentsStore: visit cap hit (\(maxVisitedFiles))")
                    break
                }

                let name = url.lastPathComponent
                if shouldSkipComponent(name) {
                    enumerator.skipDescendants()
                    continue
                }

                guard let values = try? url.resourceValues(forKeys: resourceKeys) else { continue }
                if values.isDirectory == true {
                    // Directories are not shown, but their children may be.
                    continue
                }
                guard values.isRegularFile == true else { continue }
                guard values.isPackage != true else { continue }

                let foldedName = name.searchFolded
                let matchQuality = SearchText.matchQuality(foldedName, tokens: tokens)
                if !tokens.isEmpty, matchQuality == nil { continue }

                let modified = values.contentModificationDate
                let added = values.addedToDirectoryDate
                let created = values.creationDate
                let recency = [added, modified, created].compactMap { $0 }.max() ?? .distantPast
                guard recency >= cutoff else { continue }

                let type = values.contentType
                out.append(RecentFileRecord(
                    path: url.path,
                    name: name,
                    kind: type?.localizedDescription ?? "File",
                    size: values.fileSize.map(Int64.init),
                    modified: modified,
                    dateAdded: added ?? created,
                    isFolder: false,
                    isApp: type?.conforms(to: .applicationBundle) == true,
                    recency: recency,
                    matchQuality: matchQuality ?? .substring
                ))
            }
        }

        let results = out
            .sorted {
                if $0.matchQuality != $1.matchQuality {
                    return $0.matchQuality < $1.matchQuality
                }
                if $0.recency != $1.recency { return $0.recency > $1.recency }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }

        Log.write("RecentsStore: scanned=\(visited) matched=\(out.count) returned=\(results.count) tokens=\(tokens)")
        return results
    }

    /// Scan user-facing folders first. This catches Downloads/Desktop/Pictures
    /// immediately, while still including other visible home folders.
    private func roots() -> [URL] {
        let preferred = ["Downloads", "Desktop", "Documents", "Pictures", "Movies", "Music"]
        var seen = Set<String>()
        var urls: [URL] = []

        func add(_ path: String) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }
            guard seen.insert(path).inserted else { return }
            urls.append(URL(fileURLWithPath: path, isDirectory: true))
        }

        for name in preferred { add(home + "/" + name) }

        let entries = (try? fm.contentsOfDirectory(atPath: home)) ?? []
        for entry in entries.sorted() {
            guard !entry.hasPrefix("."), entry != "Library", entry != "Applications" else { continue }
            guard !shouldSkipComponent(entry) else { continue }
            add(home + "/" + entry)
        }

        // iCloud Drive is real user content even though it lives under Library.
        add(home + "/Library/Mobile Documents/com~apple~CloudDocs")
        return urls
    }

    private func shouldSkipComponent(_ name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        let skipped: Set<String> = [
            "node_modules",
            ".git",
            ".build",
            "build",
            "dist",
            "DerivedData",
            "Caches",
            "__pycache__"
        ]
        return skipped.contains(name)
    }
}
