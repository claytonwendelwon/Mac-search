import AppKit
import Foundation

/// One row in the results list, derived from an `NSMetadataItem`.
struct SearchResult: Identifiable, Hashable {
    let id: String        // absolute path (unique + stable)
    let name: String
    let path: String
    let kind: String
    let size: Int64?
    let modified: Date?

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

/// Wraps `NSMetadataQuery` (the Spotlight index) and exposes live, filtered,
/// sorted results to SwiftUI. Queries are debounced so typing stays smooth.
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

    private let query = NSMetadataQuery()
    private let resultLimit = 60
    private var pendingSearch: DispatchWorkItem?

    init() {
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.sortDescriptors = [
            NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false),
            NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)
        ]
        query.notificationBatchingInterval = 0.15

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(queryUpdated),
                           name: .NSMetadataQueryDidFinishGathering, object: query)
        center.addObserver(self, selector: #selector(queryUpdated),
                           name: .NSMetadataQueryDidUpdate, object: query)
    }

    deinit {
        query.stop()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Search lifecycle

    private func scheduleSearch() {
        pendingSearch?.cancel()
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Nothing to search for: clear and stop.
        if trimmed.isEmpty {
            query.stop()
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
        query.stop()
        query.predicate = buildPredicate(term: term)
        query.start()
    }

    private func buildPredicate(term: String) -> NSPredicate {
        // Match each whitespace-separated token against the display name so
        // multi-word queries narrow results (all tokens must appear).
        let tokens = term.split(whereSeparator: { $0 == " " }).map(String.init)
        let namePredicates: [NSPredicate] = tokens.map {
            NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", $0)
        }
        let namePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: namePredicates)

        let trees = selectedType.contentTypeTrees
        guard !trees.isEmpty else { return namePredicate }

        let typePredicates = trees.map {
            NSPredicate(format: "kMDItemContentTypeTree == %@", $0)
        }
        let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [namePredicate, typePredicate])
    }

    // MARK: - Results

    @objc private func queryUpdated(_ note: Notification) {
        query.disableUpdates()
        defer { query.enableUpdates() }

        let count = min(query.resultCount, resultLimit)
        var rows: [SearchResult] = []
        rows.reserveCapacity(count)

        for index in 0..<count {
            guard let item = query.result(at: index) as? NSMetadataItem else { continue }
            let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            let name = (item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)
                ?? (item.value(forAttribute: NSMetadataItemFSNameKey) as? String)
            guard let path, let name else { continue }

            let kind = item.value(forAttribute: NSMetadataItemKindKey) as? String ?? ""
            let size = item.value(forAttribute: NSMetadataItemFSSizeKey) as? Int64
            let modified = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date

            rows.append(SearchResult(id: path, name: name, path: path,
                                     kind: kind, size: size, modified: modified))
        }

        results = rows
        isSearching = false
    }
}
