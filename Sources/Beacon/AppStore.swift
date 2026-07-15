import Foundation

struct AppRecord {
    let path: String
    let name: String
    let bundleIdentifier: String?
    let modified: Date?
    let lastUsed: Date?
    let foldedName: String
    let isBackgroundOnly: Bool
    let category: String
}

struct AppSearchRank: Comparable {
    let matchTier: Int
    let helperPenalty: Int
    let unmatchedCharacters: Int
    let locationPenalty: Int
    let foldedName: String

    static func < (lhs: AppSearchRank, rhs: AppSearchRank) -> Bool {
        if lhs.matchTier != rhs.matchTier { return lhs.matchTier < rhs.matchTier }
        if lhs.helperPenalty != rhs.helperPenalty { return lhs.helperPenalty < rhs.helperPenalty }
        if lhs.unmatchedCharacters != rhs.unmatchedCharacters {
            return lhs.unmatchedCharacters < rhs.unmatchedCharacters
        }
        if lhs.locationPenalty != rhs.locationPenalty {
            return lhs.locationPenalty < rhs.locationPenalty
        }
        return lhs.foldedName.localizedStandardCompare(rhs.foldedName) == .orderedAscending
    }
}

enum AppRanking {
    static func rank(name: String, path: String, bundleIdentifier: String? = nil,
                     backgroundOnly: Bool = false, tokens: [String]) -> AppSearchRank? {
        let foldedName = name.searchFolded
        let query = tokens.joined(separator: " ")
        let matchTier: Int
        if tokens.isEmpty {
            matchTier = 0
        } else if foldedName == query {
            matchTier = 0
        } else if foldedName.hasPrefix(query) {
            matchTier = 1
        } else {
            switch SearchText.matchQuality(foldedName, tokens: tokens) {
            case .exactPhrase, .wholeWords: matchTier = 2
            case .wordStarts: matchTier = 3
            case .substring: matchTier = 4
            case nil: return nil
            }
        }

        return AppSearchRank(
            matchTier: matchTier,
            helperPenalty: isHelper(name: name, path: path,
                                    bundleIdentifier: bundleIdentifier,
                                    backgroundOnly: backgroundOnly) ? 1 : 0,
            unmatchedCharacters: max(0, foldedName.count - query.count),
            locationPenalty: locationPenalty(path),
            foldedName: foldedName
        )
    }

    private static func isHelper(name: String, path: String, bundleIdentifier: String?,
                                 backgroundOnly: Bool) -> Bool {
        if backgroundOnly { return true }
        let foldedName = name.searchFolded
        let helperTerms = ["diagnostics", "synchronizer", "updater", "update helper",
                           "installer helper", "background helper"]
        if helperTerms.contains(where: foldedName.contains) { return true }
        let foldedBundleID = bundleIdentifier?.searchFolded ?? ""
        let helperComponents = [".helper", ".agent", ".updater", ".diagnostics",
                                ".synchronizer"]
        if helperComponents.contains(where: foldedBundleID.contains) { return true }
        return path.contains("/Contents/Library/")
    }

    private static func locationPenalty(_ path: String) -> Int {
        let parent = (path as NSString).deletingLastPathComponent
        if parent == NSHomeDirectory() + "/Applications" || parent == "/Applications" {
            return 0
        }
        if path.hasPrefix(NSHomeDirectory() + "/Applications/")
            || path.hasPrefix("/Applications/") {
            return 1
        }
        return 2
    }
}

/// Direct scanner for installed `.app` bundles. Spotlight often misses
/// third-party apps or apps installed outside /System/Applications; this keeps
/// the Apps filter launcher-like and predictable.
final class AppStore {
    private let fm = FileManager.default
    private let home = NSHomeDirectory()
    private let configuredRoots: [URL]?
    private let cacheLock = NSLock()
    private var cache: [AppRecord]?
    private var cacheNeedsRefresh = false

    init(roots: [URL]? = nil) {
        configuredRoots = roots
    }

    func search(tokens: [String], limit: Int = 120,
                isCancelled: (() -> Bool)? = nil) -> [AppRecord]? {
        guard let apps = loadApps(isCancelled: isCancelled) else { return nil }

        if tokens.isEmpty {
            return apps
                .sorted {
                    let left = $0.lastUsed ?? $0.modified ?? .distantPast
                    let right = $1.lastUsed ?? $1.modified ?? .distantPast
                    if left != right { return left > right }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                .prefix(limit)
                .map { $0 }
        }

        return apps
            .compactMap { app -> (AppRecord, AppSearchRank)? in
                guard let rank = AppRanking.rank(
                    name: app.name,
                    path: app.path,
                    bundleIdentifier: app.bundleIdentifier,
                    backgroundOnly: app.isBackgroundOnly,
                    tokens: tokens
                ) else { return nil }
                return (app, rank)
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                return a.0.name.localizedStandardCompare(b.0.name) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }

    func refresh() {
        cacheLock.lock()
        cacheNeedsRefresh = true
        cacheLock.unlock()
    }

    private func loadApps(isCancelled: (() -> Bool)?) -> [AppRecord]? {
        cacheLock.lock()
        let cached = cache
        let needsRefresh = cacheNeedsRefresh
        cacheLock.unlock()
        if let cached, !needsRefresh { return cached }
        var byPath: [String: AppRecord] = [:]
        var visited = 0

        for root in roots() {
            guard isCancelled?() != true else { return nil }
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey,
                                             .contentAccessDateKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                visited += 1
                if visited & 0xFF == 0, isCancelled?() == true { return nil }
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                let path = url.path
                guard byPath[path] == nil else { continue }
                byPath[path] = appRecord(at: url)
            }
        }

        let apps = byPath.values
            .sorted {
                let aRank = AppRanking.rank(name: $0.name, path: $0.path,
                                            bundleIdentifier: $0.bundleIdentifier,
                                            backgroundOnly: $0.isBackgroundOnly,
                                            tokens: [])!
                let bRank = AppRanking.rank(name: $1.name, path: $1.path,
                                            bundleIdentifier: $1.bundleIdentifier,
                                            backgroundOnly: $1.isBackgroundOnly,
                                            tokens: [])!
                return aRank < bRank
            }
        cacheLock.lock()
        cache = apps
        cacheNeedsRefresh = false
        cacheLock.unlock()
        Log.write("AppStore: loaded \(apps.count) apps")
        return apps
    }

    private func appRecord(at url: URL) -> AppRecord {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: plistURL) as? [String: Any]
        let displayName = info?["CFBundleDisplayName"] as? String
        let bundleName = info?["CFBundleName"] as? String
        let bundleIdentifier = info?["CFBundleIdentifier"] as? String
        let isBackgroundOnly = info?["LSBackgroundOnly"] as? Bool ?? false
        let rawCategory = info?["LSApplicationCategoryType"] as? String ?? ""
        let name = displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey,
                                                       .contentAccessDateKey])
        return AppRecord(path: url.path,
                         name: name,
                         bundleIdentifier: bundleIdentifier,
                         modified: values?.contentModificationDate,
                         lastUsed: values?.contentAccessDate,
                         foldedName: name.searchFolded,
                         isBackgroundOnly: isBackgroundOnly,
                         category: Self.category(for: rawCategory))
    }

    private static func category(for rawCategory: String) -> String {
        let value = rawCategory.searchFolded
        if value.contains("developer") { return "development" }
        if value.contains("graphics") || value.contains("photography")
            || value.contains("video") || value.contains("music") {
            return "creative"
        }
        if value.contains("social") || value.contains("communication") {
            return "communication"
        }
        if value.contains("utility") { return "utilities" }
        if value.contains("productivity") || value.contains("business")
            || value.contains("finance") || value.contains("education") {
            return "productivity"
        }
        return ""
    }

    private func roots() -> [URL] {
        if let configuredRoots { return configuredRoots }
        return [
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
}
