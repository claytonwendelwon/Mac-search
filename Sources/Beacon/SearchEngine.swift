import AppKit
import Foundation

/// Why a result matched the query: by its name/path, or by text found inside
/// the file's contents. Used for ranking and for the UI badge.
enum MatchKind {
    case name
    case content
}

/// Whether a result is a file/folder from the index, a text message, a note,
/// a clipboard entry, or a browser-history page.
enum ResultSource {
    case file
    case message
    case note
    case clipboard
    case history
    case settings
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
    let dateAdded: Date?  // when the file appeared in its folder (downloads/saves)
    let isFolder: Bool
    let isApp: Bool
    let contentTypes: [String]
    let matchKind: MatchKind

    /// The most recent moment the user touched this item in any way - opened,
    /// saved/modified, or added to a folder. Drives the Recents timeline.
    var effectiveRecency: Date {
        max(lastUsed ?? .distantPast,
            max(dateAdded ?? .distantPast, modified ?? .distantPast))
    }

    // Message-only fields.
    let messageBody: String?
    let messageHandle: String?  // phone/email used to open the conversation
    let messageFromMe: Bool
    let messageChatGUID: String?
    let messageRowID: Int64?

    // Note-only field: AppleScript id used to navigate to the exact note.
    let noteID: String?

    var url: URL { URL(fileURLWithPath: path) }

    var icon: NSImage {
        switch source {
        case .file:
            return NSWorkspace.shared.icon(forFile: path)
        case .message:
            return NSWorkspace.shared.icon(forFile: "/System/Applications/Messages.app")
        case .note:
            return NSWorkspace.shared.icon(forFile: "/System/Applications/Notes.app")
        case .clipboard:
            let symbol = NSImage(systemSymbolName: "doc.on.clipboard",
                                 accessibilityDescription: "Clipboard")
            return symbol ?? NSImage()
        case .history:
            let symbol = NSImage(systemSymbolName: "globe",
                                 accessibilityDescription: "Web history")
            return symbol ?? NSImage()
        case .settings:
            let symbol = NSImage(systemSymbolName: kind,
                                 accessibilityDescription: "System Settings")
            return symbol ?? NSWorkspace.shared.icon(forFile: "/System/Applications/System Settings.app")
        }
    }

    var directory: String {
        (path as NSString).deletingLastPathComponent
    }

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// File result.
    init(id: String, name: String, path: String, kind: String, size: Int64?,
         modified: Date?, lastUsed: Date?, dateAdded: Date?,
         isFolder: Bool, isApp: Bool, contentTypes: [String] = [],
         matchKind: MatchKind) {
        self.id = id; self.source = .file; self.name = name; self.path = path
        self.kind = kind; self.size = size; self.modified = modified
        self.lastUsed = lastUsed; self.dateAdded = dateAdded
        self.isFolder = isFolder; self.isApp = isApp
        self.contentTypes = contentTypes
        self.matchKind = matchKind
        self.messageBody = nil; self.messageHandle = nil; self.messageFromMe = false
        self.messageChatGUID = nil; self.messageRowID = nil
        self.noteID = nil
    }

    /// Filesystem-backed Recents result.
    init(recent r: RecentFileRecord) {
        self.id = r.path
        self.source = .file
        self.name = r.name
        self.path = r.path
        self.kind = r.kind
        self.size = r.size
        self.modified = r.modified
        self.lastUsed = r.recency
        self.dateAdded = r.dateAdded
        self.isFolder = r.isFolder
        self.isApp = r.isApp
        self.contentTypes = []
        self.matchKind = .name
        self.messageBody = nil
        self.messageHandle = nil
        self.messageFromMe = false
        self.messageChatGUID = nil
        self.messageRowID = nil
        self.noteID = nil
    }

    /// Installed app result.
    init(app a: AppRecord) {
        self.id = a.path
        self.source = .file
        self.name = a.name
        self.path = a.path
        self.kind = "Application"
        self.size = nil
        self.modified = a.modified
        self.lastUsed = nil
        self.dateAdded = nil
        self.isFolder = false
        self.isApp = true
        self.contentTypes = ["com.apple.application"]
        self.matchKind = .name
        self.messageBody = nil
        self.messageHandle = nil
        self.messageFromMe = false
        self.messageChatGUID = nil
        self.messageRowID = nil
        self.noteID = nil
    }

    /// Message result. `contactName` (when resolved from Contacts) is shown
    /// instead of the raw phone/email.
    init(message m: MessageRecord, contactName: String?) {
        self.id = "msg:\(m.rowid)"
        self.source = .message
        let who: String
        if !m.chatName.isEmpty {
            who = m.chatName
        } else if m.isGroup {
            who = "Group Chat"
        } else {
            who = contactName ?? (m.conversationHandle.isEmpty
                ? (m.isFromMe ? "You" : "Unknown")
                : m.conversationHandle)
        }
        self.name = who
        self.path = ""
        self.kind = "Message"
        self.size = nil
        self.modified = m.date
        self.lastUsed = m.date
        self.dateAdded = nil
        self.isFolder = false
        self.isApp = false
        self.contentTypes = []
        self.matchKind = .content
        self.messageBody = m.text
        self.messageHandle = m.conversationHandle
        self.messageFromMe = m.isFromMe
        self.messageChatGUID = m.chatGUID.isEmpty ? nil : m.chatGUID
        self.messageRowID = m.rowid
        self.noteID = nil
    }

    /// Note result. The note title is the title; the body/snippet is the detail.
    init(note n: NoteRecord) {
        self.id = "note:\(n.pk)"
        self.source = .note
        self.name = n.title
        self.path = ""
        self.kind = "Note"
        self.size = nil
        self.modified = n.modified
        self.lastUsed = n.modified
        self.dateAdded = nil
        self.isFolder = false
        self.isApp = false
        self.contentTypes = []
        self.matchKind = .content
        self.messageBody = n.body.isEmpty ? n.snippet : n.body
        self.messageHandle = nil
        self.messageFromMe = false
        self.messageChatGUID = nil
        self.messageRowID = nil
        self.noteID = n.appleScriptID
    }

    /// Clipboard-history result. `name` is a one-line preview; `messageBody`
    /// holds the full copied text (used for the snippet and copy-back).
    init(clip c: ClipEntry) {
        self.id = "clip:\(c.id)"
        self.source = .clipboard
        let firstLine = c.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? c.text
        self.name = firstLine.trimmingCharacters(in: .whitespaces)
        self.path = ""
        self.kind = c.app ?? "Clipboard"
        self.size = nil
        self.modified = c.date
        self.lastUsed = c.date
        self.dateAdded = nil
        self.isFolder = false
        self.isApp = false
        self.contentTypes = []
        self.matchKind = .content
        self.messageBody = c.text
        self.messageHandle = nil
        self.messageFromMe = false
        self.messageChatGUID = nil
        self.messageRowID = nil
        self.noteID = nil
    }

    /// Browser-history result. `name` is the page title (or URL), `path` holds
    /// the URL (opened on Return), `kind` the browser, `messageBody` the URL for
    /// the subtitle/copy.
    init(history h: HistoryEntry) {
        self.id = "hist:\(h.url)"
        self.source = .history
        self.name = h.title.isEmpty ? h.url : h.title
        self.path = h.url
        self.kind = h.browser
        self.size = nil
        self.modified = h.lastVisit
        self.lastUsed = h.lastVisit
        self.dateAdded = nil
        self.isFolder = false
        self.isApp = false
        self.contentTypes = []
        self.matchKind = .content
        self.messageBody = h.url
        self.messageHandle = nil
        self.messageFromMe = false
        self.messageChatGUID = nil
        self.messageRowID = nil
        self.noteID = nil
    }

    /// System Settings result.
    init(setting s: SettingRecord) {
        self.id = "setting:\(s.id)"
        self.source = .settings
        self.name = s.title
        self.path = s.url
        self.kind = s.symbol
        self.size = nil
        self.modified = nil
        self.lastUsed = nil
        self.dateAdded = nil
        self.isFolder = false
        self.isApp = false
        self.contentTypes = []
        self.matchKind = .name
        self.messageBody = s.subtitle
        self.messageHandle = nil
        self.messageFromMe = false
        self.messageChatGUID = nil
        self.messageRowID = nil
        self.noteID = nil
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
        didSet {
            guard oldValue != selectedType else { return }
            // Switching filters always starts fresh: drop the previous list and
            // any in-flight work so results from the old filter can never bleed
            // into the new one.
            fileResults = []
            messageResults = []
            noteResults = []
            results = []
            needsFullDiskAccess = false
            historySafariDenied = false
            scheduleSearch()
        }
    }
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var isSearching: Bool = false

    /// True when the Messages filter is active but we can't read the Messages
    /// database because Full Disk Access hasn't been granted.
    @Published private(set) var needsFullDiskAccess: Bool = false

    /// True in the History filter when Safari's history is locked behind Full
    /// Disk Access (other browsers may still have loaded). Drives a slim footer
    /// rather than blocking the whole results list.
    @Published private(set) var historySafariDenied: Bool = false

    /// Bumped by the app delegate to ask the search field to (re)take focus.
    @Published var focusRequestToken: Int = 0

    private let nameQuery = NSMetadataQuery()
    private let contentQuery = NSMetadataQuery()
    private let homePath = NSHomeDirectory()

    private let messageStore = MessageStore()
    private let notesStore = NotesStore()
    private let historyStore = BrowserHistoryStore()
    private let recentsStore = RecentsStore()
    private let appStore = AppStore()
    private let settingsStore = SettingsStore()
    private let contacts = ContactResolver()
    private let messageQueue = DispatchQueue(label: "com.beacon.messages", qos: .userInitiated)
    private let recentsQueue = DispatchQueue(label: "com.beacon.recents", qos: .userInitiated)
    /// Monotonic generation bumped on every scheduled search (query OR filter
    /// change). Async work captures the value and only applies its results if
    /// the token still matches - so stale/superseded searches are dropped.
    private var searchToken = 0

    /// Thread-safe mirror of `searchToken`, readable from the background scan
    /// so an in-flight store search can abort mid-scan the moment it's
    /// superseded. Without this, slow scans (a rare word across a huge
    /// Messages history) pile up on the serial queue, every publish gets
    /// dropped as stale, and the UI wedges on old results until relaunch.
    private final class Generation: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func set(_ newValue: Int) { lock.lock(); value = newValue; lock.unlock() }
        var current: Int { lock.lock(); defer { lock.unlock() }; return value }
    }
    private let liveToken = Generation()

    /// Cancellation probe for a store scan started under `token`.
    private func cancellation(for token: Int) -> () -> Bool {
        { [liveToken] in liveToken.current != token }
    }

    // Read generous caps so rarely-used items aren't dropped before ranking.
    private let nameReadCap = 500
    private let contentReadCap = 250
    private let displayCap = 120
    /// Recents reads deeper than regular searches: it is scoped to the user's
    /// own folders, but a burst of new files (a build, an export) shouldn't
    /// push a fresh download out of the readable window.
    private let recentsReadCap = 1500

    // Per-source buckets, merged in `.all` mode by `publish()`.
    private var fileResults: [SearchResult] = []
    private var scannedAppResults: [SearchResult] = []
    private var messageResults: [SearchResult] = []
    private var noteResults: [SearchResult] = []

    // Caps for the blended "All" view so each source stays reachable.
    private let allFileCap = 60
    private let allMessageCap = 6
    private let allNoteCap = 6

    private var pendingSearch: DispatchWorkItem?
    private var currentTokens: [String] = []
    private var allIncludedTypes = Set(FileType.allCases.filter(\.includedInAll))

    /// Content search (text inside files) only kicks in once the query is long
    /// enough to be meaningful; 1-2 characters would drown the list in noise
    /// and slow the query down. Name search still runs from the first character.
    private let contentMinQueryLength = 3
    /// Whether the content query was started for the current search. When it
    /// wasn't, its stale results from a previous search must not be read.
    private var contentQueryActive = false

    /// Applies the user's visible filter selection to the blended All view.
    /// Hidden filters stop contributing immediately.
    func updateAllIncludedTypes(_ types: Set<FileType>) {
        guard allIncludedTypes != types else { return }
        allIncludedTypes = types
        if selectedType == .all { scheduleSearch() }
    }

    private static let defaultSortDescriptors = [
        NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false),
        NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)
    ]

    init() {
        for query in [nameQuery, contentQuery] {
            query.searchScopes = [NSMetadataQueryLocalComputerScope]
            query.sortDescriptors = Self.defaultSortDescriptors
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
        // Bump the generation up front so any in-flight async search is
        // invalidated immediately (the moment the query or filter changes).
        // Mirroring into `liveToken` lets background scans abort mid-loop.
        searchToken &+= 1
        liveToken.set(searchToken)
        let token = searchToken
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            nameQuery.stop()
            contentQuery.stop()
            contentQueryActive = false
            currentTokens = []
            fileResults = []
            scannedAppResults = []
            messageResults = []
            noteResults = []
            // Clipboard, History & Recents show recent items when the query
            // is empty - they're browsable lists, not just search targets.
            if selectedType.isClipboard {
                results = ClipboardStore.shared.recent().map { SearchResult(clip: $0) }
                isSearching = false
            } else if selectedType.isHistory {
                results = []
                isSearching = true
                searchHistory(tokens: [], token: token)
            } else if selectedType.isRecents {
                results = []
                isSearching = true
                searchRecents(tokens: [], token: token)
            } else if selectedType.isApps {
                results = []
                isSearching = true
                searchApps(tokens: [], token: token)
            } else if selectedType.isSettings {
                results = settingsStore.search(tokens: []).map { SearchResult(setting: $0) }
                isSearching = false
            } else {
                results = []
                isSearching = false
            }
            if selectedType.needsFullDiskAccess { checkDatabaseAccess() }
            return
        }

        // Show the searching state right away so a just-cleared list doesn't
        // flash "No results" during the debounce window.
        isSearching = true

        let work = DispatchWorkItem { [weak self] in
            self?.runSearch(term: trimmed, token: token)
        }
        pendingSearch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func runSearch(term: String, token: Int) {
        guard token == searchToken else { return } // superseded before we ran
        isSearching = true
        currentTokens = SearchText.tokens(term)

        if selectedType.isMessages {
            searchMessages(tokens: currentTokens, token: token)
            return
        }
        if selectedType.isNotes {
            searchNotes(tokens: currentTokens, token: token)
            return
        }
        if selectedType.isClipboard {
            searchClipboard(tokens: currentTokens)
            return
        }
        if selectedType.isHistory {
            searchHistory(tokens: currentTokens, token: token)
            return
        }
        if selectedType.isRecents {
            needsFullDiskAccess = false
            searchRecents(tokens: currentTokens, token: token)
            return
        }
        if selectedType.isApps {
            needsFullDiskAccess = false
            searchApps(tokens: currentTokens, token: token)
            return
        }
        if selectedType.isSettings {
            nameQuery.stop()
            contentQuery.stop()
            contentQueryActive = false
            needsFullDiskAccess = false
            results = settingsStore.search(tokens: currentTokens).map { SearchResult(setting: $0) }
            isSearching = false
            return
        }
        needsFullDiskAccess = false

        let trees = selectedType.contentTypeTrees

        nameQuery.stop()
        nameQuery.searchScopes = [NSMetadataQueryLocalComputerScope]
        nameQuery.sortDescriptors = Self.defaultSortDescriptors
        nameQuery.predicate = namePredicate(tokens: currentTokens, trees: trees)
        nameQuery.start()

        contentQuery.stop()
        contentQueryActive = term.count >= contentMinQueryLength
        if contentQueryActive {
            contentQuery.searchScopes = [NSMetadataQueryLocalComputerScope]
            contentQuery.sortDescriptors = Self.defaultSortDescriptors
            contentQuery.predicate = contentPredicate(tokens: currentTokens, trees: trees)
            contentQuery.start()
        }

        // In "All" mode, also fold in (best-effort) messages and notes. Clear
        // the prior buckets so stale rows don't linger until the gather lands.
        scannedAppResults = []
        messageResults = []
        noteResults = []
        if selectedType == .all {
            if allIncludedTypes.contains(.apps) {
                gatherAppsForAll(tokens: currentTokens, token: token)
            }
            if allIncludedTypes.contains(.messages) || allIncludedTypes.contains(.notes) {
                gatherDatabasesForAll(tokens: currentTokens, token: token)
            }
        }
    }

    /// In All mode, supplement Spotlight with a direct app-folder scan so
    /// third-party apps show up even when Spotlight's app metadata misses them.
    private func gatherAppsForAll(tokens: [String], token: Int) {
        recentsQueue.async { [weak self] in
            guard let self else { return }
            let mapped = self.appStore.search(tokens: tokens, limit: 12,
                                              isCancelled: self.cancellation(for: token))
                .map { SearchResult(app: $0) }

            DispatchQueue.main.async {
                guard token == self.searchToken, self.selectedType == .all else { return }
                self.scannedAppResults = mapped
                self.publish()
            }
        }
    }

    /// Background-load and search Messages + Notes for the blended All view.
    /// Skips any source that lacks Full Disk Access (no prompt in All mode -
    /// the dedicated chips own that flow).
    private func gatherDatabasesForAll(tokens: [String], token: Int) {
        let includeMessages = allIncludedTypes.contains(.messages)
        let includeNotes = allIncludedTypes.contains(.notes)
        messageQueue.async { [weak self] in
            guard let self else { return }
            let cancelled = self.cancellation(for: token)
            var msgs: [SearchResult] = []
            if includeMessages {
                self.messageStore.ensureLoaded()
                self.contacts.ensureLoaded()
                let resolver: ((String) -> String?)? =
                    self.contacts.isReady ? { self.contacts.name(for: $0) } : nil
                if !self.messageStore.needsFullDiskAccess {
                    msgs = self.messageStore.search(tokens: tokens, limit: self.allMessageCap,
                                                    nameResolver: resolver, isCancelled: cancelled)
                        .map {
                            SearchResult(message: $0,
                                         contactName: self.contacts.name(for: $0.conversationHandle))
                        }
                }
            }

            var notes: [SearchResult] = []
            if includeNotes {
                self.notesStore.ensureLoaded()
                if !self.notesStore.needsFullDiskAccess {
                    notes = self.notesStore.search(tokens: tokens, limit: self.allNoteCap,
                                                   isCancelled: cancelled).map { SearchResult(note: $0) }
                }
            }

            DispatchQueue.main.async {
                guard token == self.searchToken, self.selectedType == .all else { return }
                self.messageResults = msgs
                self.noteResults = notes
                self.publish()
            }
        }
    }

    /// Combine the per-source buckets into the published `results`. In `.all`
    /// mode the sources are grouped (files, then messages, then notes); other
    /// file-backed modes show just their files.
    private func publish() {
        if selectedType == .all {
            let filesAndApps = mergeScannedApps(into: fileResults).prefix(allFileCap)
            var combined: [SearchResult] = []
            combined += filesAndApps
            if allIncludedTypes.contains(.messages) {
                combined += messageResults.prefix(allMessageCap)
            }
            if allIncludedTypes.contains(.notes) {
                combined += noteResults.prefix(allNoteCap)
            }
            results = Array(combined.prefix(displayCap))
        } else {
            results = fileResults
        }
    }

    private func mergeScannedApps(into fileRows: [SearchResult]) -> [SearchResult] {
        guard !scannedAppResults.isEmpty else { return fileRows }
        var byID: [String: SearchResult] = [:]
        for row in fileRows { byID[row.id] = row }
        for row in scannedAppResults { byID[row.id] = row }
        return byID.values
            .map { (result: $0, score: score($0)) }
            .sorted { a, b in
                if a.score != b.score { return a.score < b.score }
                let da = a.result.lastUsed ?? a.result.modified ?? .distantPast
                let db = b.result.lastUsed ?? b.result.modified ?? .distantPast
                if da != db { return da > db }
                return a.result.name.localizedCaseInsensitiveCompare(b.result.name) == .orderedAscending
            }
            .map(\.result)
    }

    // MARK: - Messages

    private func searchMessages(tokens: [String], token: Int) {
        nameQuery.stop()
        contentQuery.stop()
        contentQueryActive = false

        messageQueue.async { [weak self] in
            guard let self else { return }
            self.messageStore.ensureLoaded()
            self.contacts.ensureLoaded()
            let needsAccess = self.messageStore.needsFullDiskAccess
            let resolver: ((String) -> String?)? =
                self.contacts.isReady ? { self.contacts.name(for: $0) } : nil
            let hits = self.messageStore.search(tokens: tokens, nameResolver: resolver,
                                                isCancelled: self.cancellation(for: token))
            let mapped = hits.map { rec in
                SearchResult(message: rec,
                             contactName: self.contacts.name(for: rec.conversationHandle))
            }

            DispatchQueue.main.async {
                // Drop if superseded, or if the user has since left Messages.
                guard token == self.searchToken, self.selectedType.isMessages else { return }
                self.needsFullDiskAccess = needsAccess
                self.results = mapped
                self.isSearching = false
            }
        }
    }

    // MARK: - Notes

    private func searchNotes(tokens: [String], token: Int) {
        nameQuery.stop()
        contentQuery.stop()
        contentQueryActive = false

        messageQueue.async { [weak self] in
            guard let self else { return }
            self.notesStore.ensureLoaded()
            let needsAccess = self.notesStore.needsFullDiskAccess
            let mapped = self.notesStore.search(tokens: tokens,
                                                isCancelled: self.cancellation(for: token))
                .map { SearchResult(note: $0) }

            DispatchQueue.main.async {
                guard token == self.searchToken, self.selectedType.isNotes else { return }
                self.needsFullDiskAccess = needsAccess
                self.results = mapped
                self.isSearching = false
            }
        }
    }

    // MARK: - Clipboard

    private func searchClipboard(tokens: [String]) {
        nameQuery.stop()
        contentQuery.stop()
        contentQueryActive = false
        needsFullDiskAccess = false
        results = ClipboardStore.shared.search(tokens: tokens).map { SearchResult(clip: $0) }
        isSearching = false
    }

    // MARK: - Browser history

    private func searchHistory(tokens: [String], token: Int) {
        nameQuery.stop()
        contentQuery.stop()
        contentQueryActive = false

        messageQueue.async { [weak self] in
            guard let self else { return }
            self.historyStore.ensureLoaded()
            let safariDenied = self.historyStore.safariDenied
            let mapped = self.historyStore.search(tokens: tokens,
                                                  isCancelled: self.cancellation(for: token))
                .map { SearchResult(history: $0) }

            DispatchQueue.main.async {
                guard token == self.searchToken, self.selectedType.isHistory else { return }
                // History never blocks the whole list; Safari denial surfaces
                // as a slim footer instead.
                self.needsFullDiskAccess = false
                self.historySafariDenied = safariDenied
                self.results = mapped
                self.isSearching = false
            }
        }
    }

    // MARK: - Recents

    private func searchRecents(tokens: [String], token: Int) {
        nameQuery.stop()
        contentQuery.stop()
        contentQueryActive = false
        needsFullDiskAccess = false

        recentsQueue.async { [weak self] in
            guard let self else { return }
            let rows = self.recentsStore.search(tokens: tokens,
                                                isCancelled: self.cancellation(for: token))
            let mapped = rows.map { SearchResult(recent: $0) }

            DispatchQueue.main.async {
                guard token == self.searchToken, self.selectedType.isRecents else { return }
                self.fileResults = mapped
                self.results = mapped
                self.isSearching = false
            }
        }
    }

    // MARK: - Apps

    private func searchApps(tokens: [String], token: Int) {
        nameQuery.stop()
        contentQuery.stop()
        contentQueryActive = false
        needsFullDiskAccess = false

        recentsQueue.async { [weak self] in
            guard let self else { return }
            let rows = self.appStore.search(tokens: tokens,
                                            isCancelled: self.cancellation(for: token))
            let mapped = rows.map { SearchResult(app: $0) }

            DispatchQueue.main.async {
                guard token == self.searchToken, self.selectedType.isApps else { return }
                self.fileResults = mapped
                self.results = mapped
                self.isSearching = false
            }
        }
    }

    /// Probe the protected databases once at launch. Attempting to open them
    /// registers Beacon with macOS's privacy system, so the app shows up
    /// (toggleable) in the Full Disk Access list without the user having to add
    /// it manually with the "+" button.
    func warmMessageAccess() {
        messageQueue.async { [weak self] in
            guard let self else { return }
            self.messageStore.ensureLoaded()
            self.notesStore.ensureLoaded()
            self.historyStore.ensureLoaded()
            let needsAccess = self.messageStore.needsFullDiskAccess
            DispatchQueue.main.async { self.needsFullDiskAccess = needsAccess }
        }
    }

    /// Confirm access for the active database-backed filter so the Full Disk
    /// Access prompt can appear even before the user types anything.
    private func checkDatabaseAccess() {
        let wantsNotes = selectedType.isNotes
        messageQueue.async { [weak self] in
            guard let self else { return }
            let needsAccess: Bool
            if wantsNotes {
                self.notesStore.ensureLoaded()
                needsAccess = self.notesStore.needsFullDiskAccess
            } else {
                self.messageStore.ensureLoaded()
                needsAccess = self.messageStore.needsFullDiskAccess
            }
            DispatchQueue.main.async { self.needsFullDiskAccess = needsAccess }
        }
    }

    /// Re-run the current query whenever the panel is summoned. Guarantees the
    /// list reflects the world *now* (fresh downloads in Recents, new messages,
    /// new clipboard entries) and self-heals any view that wedged on a stale
    /// publish - without waiting for the user to retype.
    func refreshForPanelShow() {
        scheduleSearch()
    }

    /// Re-attempt loading the protected DBs (e.g. after the user grants access),
    /// then re-run the current search if we're in a database-backed mode.
    func retryMessageAccess() {
        messageStore.retry()
        notesStore.retry()
        historyStore.retry()
        if selectedType.needsFullDiskAccess { scheduleSearch() }
    }

    // MARK: - Predicates

    /// Each token must appear in the display name OR the on-disk file name.
    private func namePredicate(tokens: [String], trees: [String],
                               excludedTrees: [String] = []) -> NSPredicate {
        let perToken: [NSPredicate] = tokens.map { token in
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", token),
                NSPredicate(format: "kMDItemFSName CONTAINS[cd] %@", token)
            ])
        }
        let base = Self.combine(perToken, type: .and) ?? NSPredicate(value: true)
        return applyTypeFilter(base, trees: trees, excludedTrees: excludedTrees)
    }

    /// Each token must appear in the indexed text contents of the file.
    private func contentPredicate(tokens: [String], trees: [String],
                                  excludedTrees: [String] = []) -> NSPredicate {
        let perToken = tokens.map { NSPredicate(format: "kMDItemTextContent CONTAINS[cd] %@", $0) }
        let base = Self.combine(perToken, type: .and) ?? NSPredicate(value: true)
        return applyTypeFilter(base, trees: trees, excludedTrees: excludedTrees)
    }

    private func applyTypeFilter(_ base: NSPredicate, trees: [String],
                                 excludedTrees: [String]) -> NSPredicate {
        var predicates = [base]
        if !trees.isEmpty {
            let typePredicates = trees.map { NSPredicate(format: "kMDItemContentTypeTree == %@", $0) }
            if let included = Self.combine(typePredicates, type: .or) {
                predicates.append(included)
            }
        }
        predicates += excludedTrees.map {
            NSCompoundPredicate(notPredicateWithSubpredicate:
                NSPredicate(format: "kMDItemContentTypeTree == %@", $0))
        }
        return Self.combine(predicates, type: .and) ?? base
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
        // Ignore late file-index notifications while a database-backed filter
        // (Messages/Notes/Clipboard/History) is active, so they can't overwrite
        // that filter's results.
        guard selectedType.usesFileIndex else { return }

        var merged: [String: SearchResult] = [:]

        // Name matches first so they win on dedupe against content matches.
        readResults(from: nameQuery, cap: nameReadCap, matchKind: .name, into: &merged)
        if contentQueryActive {
            readResults(from: contentQuery, cap: contentReadCap, matchKind: .content, into: &merged)
        }

        // Score once per result (folding is not free), then sort.
        fileResults = merged.values
            .map { (result: $0, score: score($0)) }
            .sorted { a, b in
                if a.score != b.score { return a.score < b.score }
                let da = a.result.lastUsed ?? a.result.modified ?? .distantPast
                let db = b.result.lastUsed ?? b.result.modified ?? .distantPast
                if da != db { return da > db }
                return a.result.name.localizedCaseInsensitiveCompare(b.result.name) == .orderedAscending
            }
            .prefix(displayCap)
            .map(\.result)
        publish()

        let bothDone = !nameQuery.isGathering
            && (!contentQueryActive || !contentQuery.isGathering)
        if bothDone { isSearching = false }
    }

    private func readResults(from query: NSMetadataQuery, cap: Int,
                             matchKind: MatchKind, into merged: inout [String: SearchResult]) {
        query.disableUpdates()
        defer { query.enableUpdates() }

        // Hidden categories may occupy any number of leading Spotlight rows.
        // Continue until enough accepted rows are found so customization never
        // makes valid visible results disappear behind an arbitrary pre-cap.
        let count = selectedType == .all ? query.resultCount : min(query.resultCount, cap)
        var added = 0
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
            let dateAdded = item.value(forAttribute: NSMetadataItemDateAddedKey) as? Date
            let contentType = item.value(forAttribute: NSMetadataItemContentTypeTreeKey) as? [String] ?? []
            let isFolder = contentType.contains("public.folder")
            let isApp = contentType.contains("com.apple.application")

            let result = SearchResult(id: path, name: name, path: path, kind: kind,
                                      size: size, modified: modified, lastUsed: lastUsed,
                                      dateAdded: dateAdded,
                                      isFolder: isFolder, isApp: isApp,
                                      contentTypes: contentType, matchKind: matchKind)
            if selectedType == .all && !isIncludedInAll(result) { continue }
            merged[path] = result
            added += 1
            if added >= cap { break }
        }
    }

    /// Assign each indexed item to its most specific filter so overlapping UTI
    /// trees (for example PDF also conforming to document) do not cause hiding
    /// Docs to accidentally suppress a still-visible PDF source.
    private func isIncludedInAll(_ result: SearchResult) -> Bool {
        let type: FileType?
        if result.isApp {
            type = .apps
        } else if result.isFolder {
            type = .folders
        } else if result.contentTypes.contains("com.adobe.pdf") {
            type = .pdfs
        } else if result.contentTypes.contains("public.image") {
            type = .photos
        } else if result.contentTypes.contains("public.movie") {
            type = .videos
        } else if result.contentTypes.contains("public.audio") {
            type = .audio
        } else if !Set(result.contentTypes).isDisjoint(with: Set(FileType.docs.contentTypeTrees)) {
            type = .docs
        } else {
            type = nil // Unknown file types remain part of broad local search.
        }
        return type.map(allIncludedTypes.contains) ?? true
    }

    // MARK: - Ranking

    /// Lower score sorts first (ties broken by most-recently-used, then name).
    ///
    /// Tiers, best to worst:
    ///   0   exact name — with or without the extension, so "report" exact-
    ///       matches "report.pdf", the way a launcher is expected to
    ///   100 name starts with the whole query ("saf" -> Safari)
    ///   200 every token is a whole word in the name ("main" beats "maintain")
    ///   250 every token starts a word in the name ("chase stat" ->
    ///       "Chase Statement.pdf")
    ///   300 every token appears somewhere in the name
    ///   400 matched only on the path / on-disk name
    ///   500 matched by text inside the file
    /// Within a tier: apps first (launcher expectation), then folders, then
    /// the user's own files over system paths.
    private func score(_ r: SearchResult) -> Int {
        let name = r.name.searchFolded
        let stem = (r.name as NSString).deletingPathExtension.searchFolded
        let query = currentTokens.joined(separator: " ")
        var base: Int
        if r.matchKind == .content {
            base = 500
        } else if name == query || stem == query {
            base = 0
        } else if name.hasPrefix(query) || stem.hasPrefix(query) {
            base = 100
        } else if currentTokens.allSatisfy({ SearchText.hasWholeWord(name, $0) }) {
            base = 200
        } else if currentTokens.allSatisfy({ SearchText.hasWordStart(name, $0) }) {
            base = 250
        } else if currentTokens.allSatisfy({ name.contains($0) }) {
            base = 300
        } else {
            base = 400
        }
        if r.isApp { base -= 50 }                     // launching apps is the top use case
        if r.isFolder { base -= 10 }                  // nudge folders up within their tier
        if r.path.hasPrefix(homePath) { base -= 30 }  // prefer the user's own files
        return base
    }
}
