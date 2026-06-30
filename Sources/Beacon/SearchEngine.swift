import AppKit
import Foundation

/// Why a result matched the query: by its name/path, or by text found inside
/// the file's contents. Used for ranking and for the UI badge.
enum MatchKind {
    case name
    case content
}

/// Whether a result is a file/folder from the index, or a text message.
enum ResultSource {
    case file
    case message
}

/// One row in the results list, from either the Spotlight index or Messages.
struct SearchResult: Identifiable, Hashable {
    let id: String        // unique + stable (file path, or "msg:<rowid>")
    let source: ResultSource
    let name: String      // file name, or the message's sender/contact
    let path: String      // file path; "" for messages
    let kind: String
    let size: Int64?
    let modified: Date?
    let lastUsed: Date?
    let isFolder: Bool
    let matchKind: MatchKind

    // Message-only fields.
    let messageBody: String?
    let messageHandle: String?  // phone/email used to open the conversation

    var url: URL { URL(fileURLWithPath: path) }

    var icon: NSImage {
        switch source {
        case .file:
            return NSWorkspace.shared.icon(forFile: path)
        case .message:
            return NSWorkspace.shared.icon(forFile: "/System/Applications/Messages.app")
        }
    }

    var directory: String {
        (path as NSString).deletingLastPathComponent
    }

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// File result.
    init(id: String, name: String, path: String, kind: String, size: Int64?,
         modified: Date?, lastUsed: Date?, isFolder: Bool, matchKind: MatchKind) {
        self.id = id; self.source = .file; self.name = name; self.path = path
        self.kind = kind; self.size = size; self.modified = modified
        self.lastUsed = lastUsed; self.isFolder = isFolder; self.matchKind = matchKind
        self.messageBody = nil; self.messageHandle = nil
    }

    /// Message result.
    init(message m: MessageRecord) {
        self.id = "msg:\(m.rowid)"
        self.source = .message
        let who = m.handle.isEmpty ? "Message" : m.handle
        self.name = m.isFromMe ? "You \u{2192} \(who)" : who
        self.path = ""
        self.kind = "Message"
        self.size = nil
        self.modified = m.date
        self.lastUsed = m.date
        self.isFolder = false
        self.matchKind = .content
        self.messageBody = m.text
        self.messageHandle = m.handle
    }
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

    /// True when the Messages filter is active but we can't read the Messages
    /// database because Full Disk Access hasn't been granted.
    @Published private(set) var needsFullDiskAccess: Bool = false

    /// Bumped by the app delegate to ask the search field to (re)take focus.
    @Published var focusRequestToken: Int = 0

    private let nameQuery = NSMetadataQuery()
    private let contentQuery = NSMetadataQuery()
    private let homePath = NSHomeDirectory()

    private let messageStore = MessageStore()
    private let messageQueue = DispatchQueue(label: "com.beacon.messages", qos: .userInitiated)
    private var messageSearchID = 0

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
            if selectedType.isMessages { checkMessageAccess() }
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

        if selectedType.isMessages {
            searchMessages(tokens: currentTokens)
            return
        }
        needsFullDiskAccess = false

        let trees = selectedType.contentTypeTrees

        nameQuery.stop()
        nameQuery.predicate = namePredicate(tokens: currentTokens, trees: trees)
        nameQuery.start()

        contentQuery.stop()
        contentQuery.predicate = contentPredicate(tokens: currentTokens, trees: trees)
        contentQuery.start()
    }

    // MARK: - Messages

    private func searchMessages(tokens: [String]) {
        nameQuery.stop()
        contentQuery.stop()

        messageSearchID += 1
        let searchID = messageSearchID

        messageQueue.async { [weak self] in
            guard let self else { return }
            self.messageStore.ensureLoaded()
            let needsAccess = self.messageStore.needsFullDiskAccess
            let hits = self.messageStore.search(tokens: tokens)
            let mapped = hits.map { SearchResult(message: $0) }

            DispatchQueue.main.async {
                guard searchID == self.messageSearchID else { return } // stale
                self.needsFullDiskAccess = needsAccess
                self.results = mapped
                self.isSearching = false
            }
        }
    }

    /// Probe Messages access once at launch. Attempting to open the protected
    /// database registers Beacon with macOS's privacy system, so the app shows
    /// up (toggleable) in the Full Disk Access list without the user having to
    /// add it manually with the "+" button.
    func warmMessageAccess() {
        checkMessageAccess()
    }

    /// Load (or confirm) Messages access in the background so the Full Disk
    /// Access prompt can appear even before the user types anything.
    private func checkMessageAccess() {
        messageQueue.async { [weak self] in
            guard let self else { return }
            self.messageStore.ensureLoaded()
            let needsAccess = self.messageStore.needsFullDiskAccess
            DispatchQueue.main.async { self.needsFullDiskAccess = needsAccess }
        }
    }

    /// Re-attempt loading the Messages DB (e.g. after the user grants access),
    /// then re-run the current search if we're in Messages mode.
    func retryMessageAccess() {
        messageStore.retry()
        if selectedType.isMessages { scheduleSearch() }
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
