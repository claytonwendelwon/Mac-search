import AppKit
import Foundation

/// Why a result matched the query: by its name/path, or by text found inside
/// the file's contents. Used for ranking and for the UI badge.
enum MatchKind {
    case name
    case content
}

/// One row in the results list, derived from an `NSMetadataItem`.
struct SearchResult: Identifiable, Hashable {
    let id: String        // absolute path (unique + stable)
    let name: String
    let path: String
    let kind: String
    let size: Int64?
    let modified: Date?
    let lastUsed: Date?
    let isFolder: Bool
    let matchKind: MatchKind

    var url: URL { URL(fileURLWithPath: path) }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }

    var directory: String {
        (path as NSString).deletingLastPathComponent
    }

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Wraps the Spotlight index via two `NSMetadataQuery` passes:
///   1. a name/path query (fast, few results) and
///   2. a document-contents query (text inside files).
/// Results are merged and ranked client-side so exact name matches always
/// surface above incidental content matches. Queries are debounced.
final class SearchEngine: ObservableObject {
    @Published var queryText: String = "" {
        didSet { scheduleSearch() }
    }
    @Published var selectedType: FileType = .all {
        didSet { scheduleSearch() }
    }
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var isSearching: Bool = false

    /// Bumped by the app delegate to ask the search field to (re)take focus.
    @Published var focusRequestToken: Int = 0

    private let nameQuery = NSMetadataQuery()
    private let contentQuery = NSMetadataQuery()
    private let homePath = NSHomeDirectory()

    // Read generous caps so rarely-used items aren't dropped before ranking.
    private let nameReadCap = 500
    private let contentReadCap = 250
    private let displayCap = 120

    private var pendingSearch: DispatchWorkItem?
    private var currentTokens: [String] = []

    init() {
        for query in [nameQuery, contentQuery] {
            query.searchScopes = [NSMetadataQueryLocalComputerScope]
            query.sortDescriptors = [
                NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false),
                NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)
            ]
            query.notificationBatchingInterval = 0.2
        }

        let center = NotificationCenter.default
        for query in [nameQuery, contentQuery] {
            center.addObserver(self, selector: #selector(queryUpdated),
                               name: .NSMetadataQueryDidFinishGathering, object: query)
            center.addObserver(self, selector: #selector(queryUpdated),
                               name: .NSMetadataQueryDidUpdate, object: query)
        }
    }

    deinit {
        nameQuery.stop()
        contentQuery.stop()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Search lifecycle

    private func scheduleSearch() {
        pendingSearch?.cancel()
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            nameQuery.stop()
            contentQuery.stop()
            currentTokens = []
            results = []
            isSearching = false
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.runSearch(term: trimmed)
        }
        pendingSearch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func runSearch(term: String) {
        isSearching = true
        currentTokens = term.split(whereSeparator: { $0 == " " }).map { $0.lowercased() }

        let trees = selectedType.contentTypeTrees

        nameQuery.stop()
        nameQuery.predicate = namePredicate(tokens: currentTokens, trees: trees)
        nameQuery.start()

        contentQuery.stop()
        contentQuery.predicate = contentPredicate(tokens: currentTokens, trees: trees)
        contentQuery.start()
    }

    // MARK: - Predicates

    /// Each token must appear in the display name OR the on-disk file name.
    private func namePredicate(tokens: [String], trees: [String]) -> NSPredicate {
        let perToken: [NSPredicate] = tokens.map { token in
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", token),
                NSPredicate(format: "kMDItemFSName CONTAINS[cd] %@", token)
            ])
        }
        let base = Self.combine(perToken, type: .and) ?? NSPredicate(value: true)
        return applyTypeFilter(base, trees: trees)
    }

    /// Each token must appear in the indexed text contents of the file.
    private func contentPredicate(tokens: [String], trees: [String]) -> NSPredicate {
        let perToken = tokens.map { NSPredicate(format: "kMDItemTextContent CONTAINS[cd] %@", $0) }
        let base = Self.combine(perToken, type: .and) ?? NSPredicate(value: true)
        return applyTypeFilter(base, trees: trees)
    }

    private func applyTypeFilter(_ base: NSPredicate, trees: [String]) -> NSPredicate {
        guard !trees.isEmpty else { return base }
        let typePredicates = trees.map { NSPredicate(format: "kMDItemContentTypeTree == %@", $0) }
        guard let typePredicate = Self.combine(typePredicates, type: .or) else { return base }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [base, typePredicate])
    }

    /// Combine predicates without ever producing a single-element compound
    /// (which NSMetadataQuery treats as invalid and throws on).
    private static func combine(_ predicates: [NSPredicate],
                                type: NSCompoundPredicate.LogicalType) -> NSPredicate? {
        switch predicates.count {
        case 0: return nil
        case 1: return predicates[0]
        default: return NSCompoundPredicate(type: type, subpredicates: predicates)
        }
    }

    // MARK: - Results

    @objc private func queryUpdated(_ note: Notification) {
        var merged: [String: SearchResult] = [:]

        // Name matches first so they win on dedupe against content matches.
        readResults(from: nameQuery, cap: nameReadCap, matchKind: .name, into: &merged)
        readResults(from: contentQuery, cap: contentReadCap, matchKind: .content, into: &merged)

        results = Array(merged.values)
            .sorted(by: rank)
            .prefix(displayCap)
            .map { $0 }

        let bothDone = !nameQuery.isGathering && !contentQuery.isGathering
        if bothDone { isSearching = false }
    }

    private func readResults(from query: NSMetadataQuery, cap: Int,
                             matchKind: MatchKind, into merged: inout [String: SearchResult]) {
        query.disableUpdates()
        defer { query.enableUpdates() }

        let count = min(query.resultCount, cap)
        for index in 0..<count {
            guard let item = query.result(at: index) as? NSMetadataItem else { continue }
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            if merged[path] != nil { continue } // keep the higher-priority (name) match

            let name = (item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)
                ?? (item.value(forAttribute: NSMetadataItemFSNameKey) as? String)
                ?? (path as NSString).lastPathComponent

            let kind = item.value(forAttribute: NSMetadataItemKindKey) as? String ?? ""
            let size = item.value(forAttribute: NSMetadataItemFSSizeKey) as? Int64
            let modified = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
            let lastUsed = item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date
            let contentType = item.value(forAttribute: NSMetadataItemContentTypeTreeKey) as? [String] ?? []
            let isFolder = contentType.contains("public.folder")

            merged[path] = SearchResult(id: path, name: name, path: path, kind: kind,
                                        size: size, modified: modified, lastUsed: lastUsed,
                                        isFolder: isFolder, matchKind: matchKind)
        }
    }

    // MARK: - Ranking

    /// Lower score sorts first. Name matches beat content matches; exact names
    /// beat prefixes beat substrings; folders get a small nudge; ties broken by
    /// most-recently-used / modified.
    private func rank(_ a: SearchResult, _ b: SearchResult) -> Bool {
        let sa = score(a), sb = score(b)
        if sa != sb { return sa < sb }
        let da = a.lastUsed ?? a.modified ?? .distantPast
        let db = b.lastUsed ?? b.modified ?? .distantPast
        if da != db { return da > db }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    private func score(_ r: SearchResult) -> Int {
        let lowerName = r.name.lowercased()
        let query = currentTokens.joined(separator: " ")
        var base: Int
        if r.matchKind == .content {
            base = 400
        } else if lowerName == query {
            base = 0                                   // exact name
        } else if let first = currentTokens.first, lowerName.hasPrefix(first) {
            base = 100                                 // name starts with query
        } else if currentTokens.allSatisfy({ lowerName.contains($0) }) {
            base = 200                                 // all tokens in name
        } else {
            base = 300                                 // matched on path/fs name
        }
        if r.isFolder { base -= 10 }                 // nudge folders up within their tier
        if r.path.hasPrefix(homePath) { base -= 30 }  // prefer the user's own files
        return base
    }
}
