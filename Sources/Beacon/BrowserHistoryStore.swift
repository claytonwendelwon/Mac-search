import Foundation
import SQLite3

/// A single visited page from a browser's history.
struct HistoryEntry {
    let url: String
    let title: String
    let visitCount: Int
    let lastVisit: Date
    let browser: String

    // Precomputed folded haystacks so each keystroke filters without re-folding.
    let foldedTitle: String
    let foldedURL: String

    init(url: String, title: String, visitCount: Int, lastVisit: Date, browser: String) {
        self.url = url
        self.title = title
        self.visitCount = visitCount
        self.lastVisit = lastVisit
        self.browser = browser
        self.foldedTitle = title.searchFolded
        self.foldedURL = url.searchFolded
    }
}

/// Reads and searches browser history across Safari and all Chromium-based
/// browsers (Chrome, Brave, Edge, Arc), including every profile.
///
/// Each history database is opened read-only + immutable, so we never lock the
/// file while the browser is running. Safari's history lives under the
/// TCC-protected `~/Library/Safari` folder and needs Full Disk Access; the
/// Chromium browsers store theirs under Application Support and read without it.
/// If the only thing we couldn't read was Safari (and we found nothing else),
/// we surface `.needsFullDiskAccess` so the UI can guide the user.
final class BrowserHistoryStore {
    enum State {
        case idle
        case ready
        case needsFullDiskAccess
        case unavailable
    }

    private(set) var state: State = .idle
    /// True when Safari's history exists but couldn't be read (Full Disk Access
    /// is off). Other browsers may still have loaded fine. Drives the slim
    /// in-list footer rather than a full-screen block.
    private(set) var safariDenied = false
    private var cache: [HistoryEntry] = []

    private let home = NSHomeDirectory()
    private let perSourceCap = 20_000
    private let totalCap = 40_000

    var needsFullDiskAccess: Bool { state == .needsFullDiskAccess }

    func ensureLoaded() {
        guard state == .idle else { return }
        load()
    }

    func retry() {
        state = .idle
        ensureLoaded()
    }

    /// Empty `tokens` returns the most-recently-visited pages (for the empty
    /// query state); otherwise matches title or URL and ranks by match quality
    /// plus frecency, so the page you actually use surfaces above a one-off
    /// visit that merely happens to be more recent.
    func search(tokens: [String], limit: Int = 200) -> [HistoryEntry] {
        guard state == .ready else { return [] }
        guard !tokens.isEmpty else { return Array(cache.prefix(limit)) }

        var scored: [(entry: HistoryEntry, quality: Int, frecency: Double)] = []
        for entry in cache {
            var quality = 0
            var matched = true
            for token in tokens {
                if SearchText.hasWordStart(entry.foldedTitle, token) {
                    quality += 3        // token starts a word in the title
                } else if entry.foldedTitle.contains(token) {
                    quality += 2        // token somewhere in the title
                } else if entry.foldedURL.contains(token) {
                    quality += 1        // URL-only match
                } else {
                    matched = false
                    break
                }
            }
            guard matched else { continue }
            scored.append((entry, quality, Self.frecency(entry)))
        }

        scored.sort { a, b in
            if a.quality != b.quality { return a.quality > b.quality }
            if a.frecency != b.frecency { return a.frecency > b.frecency }
            return a.entry.lastVisit > b.entry.lastVisit
        }
        return scored.prefix(limit).map(\.entry)
    }

    /// Firefox-style frecency: visit count damped by how long ago the page was
    /// last visited.
    private static func frecency(_ entry: HistoryEntry) -> Double {
        let days = -entry.lastVisit.timeIntervalSinceNow / 86_400
        let weight: Double
        switch days {
        case ..<4:   weight = 1.0
        case ..<14:  weight = 0.7
        case ..<31:  weight = 0.5
        case ..<90:  weight = 0.3
        default:     weight = 0.1
        }
        return Double(max(1, entry.visitCount)) * weight
    }

    // MARK: - Loading

    private func load() {
        var all: [HistoryEntry] = []
        safariDenied = false

        // Safari (needs Full Disk Access).
        let safariPath = home + "/Library/Safari/History.db"
        if FileManager.default.fileExists(atPath: safariPath) {
            switch readSafari(safariPath) {
            case .success(let rows): all.append(contentsOf: rows)
            case .denied: safariDenied = true
            case .none: break
            }
        }

        // Chromium browsers (read without Full Disk Access).
        let chromiumBases: [(String, String)] = [
            ("Chrome", "/Library/Application Support/Google/Chrome"),
            ("Brave",  "/Library/Application Support/BraveSoftware/Brave-Browser"),
            ("Edge",   "/Library/Application Support/Microsoft Edge"),
            ("Arc",    "/Library/Application Support/Arc/User Data")
        ]
        for (name, rel) in chromiumBases {
            for historyPath in chromiumHistoryPaths(base: home + rel) {
                all.append(contentsOf: readChromium(historyPath, browser: name))
            }
        }

        guard !all.isEmpty else {
            state = safariDenied ? .needsFullDiskAccess : .unavailable
            Log.write("BrowserHistoryStore: no entries (safariDenied=\(safariDenied))")
            return
        }

        // De-dupe by URL, keeping the most-recent visit, then sort newest-first.
        var byURL: [String: HistoryEntry] = [:]
        for entry in all {
            if let existing = byURL[entry.url], existing.lastVisit >= entry.lastVisit { continue }
            byURL[entry.url] = entry
        }
        cache = byURL.values.sorted { $0.lastVisit > $1.lastVisit }
        if cache.count > totalCap { cache.removeLast(cache.count - totalCap) }
        state = .ready
        Log.write("BrowserHistoryStore: loaded \(cache.count) entries from \(all.count) rows")
    }

    /// Find each profile's History file under a Chromium "User Data" directory
    /// (Default plus any "Profile N").
    private func chromiumHistoryPaths(base: String) -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: base) else { return [] }
        guard let entries = try? fm.contentsOfDirectory(atPath: base) else { return [] }
        var paths: [String] = []
        for entry in entries where entry == "Default" || entry.hasPrefix("Profile ") {
            let candidate = base + "/" + entry + "/History"
            if fm.fileExists(atPath: candidate) { paths.append(candidate) }
        }
        return paths
    }

    private enum SourceResult { case success([HistoryEntry]); case denied; case none }

    private func readSafari(_ path: String) -> SourceResult {
        guard let snap = openSnapshot(path) else { return .denied }
        defer { snap.cleanup() }
        let db = snap.db

        // SQLite's MAX() guarantees the bare columns come from the max-visit row.
        let sql = """
        SELECT i.url, COALESCE(v.title, ''), i.visit_count, MAX(v.visit_time)
        FROM history_items AS i
        JOIN history_visits AS v ON v.history_item = i.id
        WHERE i.url IS NOT NULL
        GROUP BY i.id
        ORDER BY MAX(v.visit_time) DESC
        LIMIT \(perSourceCap);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return .none }
        defer { sqlite3_finalize(stmt) }

        var rows: [HistoryEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let url = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let visits = Int(sqlite3_column_int64(stmt, 2))
            let cfTime = sqlite3_column_double(stmt, 3) // CFAbsoluteTime (since 2001)
            guard !url.isEmpty else { continue }
            rows.append(HistoryEntry(url: url, title: title, visitCount: visits,
                                     lastVisit: Date(timeIntervalSinceReferenceDate: cfTime),
                                     browser: "Safari"))
        }
        return .success(rows)
    }

    private func readChromium(_ path: String, browser: String) -> [HistoryEntry] {
        guard let snap = openSnapshot(path) else { return [] }
        defer { snap.cleanup() }
        let db = snap.db

        let sql = """
        SELECT url, COALESCE(title, ''), visit_count, last_visit_time
        FROM urls
        WHERE url IS NOT NULL
        ORDER BY last_visit_time DESC
        LIMIT \(perSourceCap);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [HistoryEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let url = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let visits = Int(sqlite3_column_int64(stmt, 2))
            let chromeTime = sqlite3_column_int64(stmt, 3) // micros since 1601-01-01
            guard !url.isEmpty, chromeTime > 0 else { continue }
            rows.append(HistoryEntry(url: url, title: title, visitCount: visits,
                                     lastVisit: Self.chromeDate(chromeTime),
                                     browser: browser))
        }
        return rows
    }

    // MARK: - Helpers

    /// Copy a SQLite database (plus its -wal/-shm sidecars) to a temp location
    /// and open the copy, so we pick up recent writes still living in the WAL.
    ///
    /// Browsers run in WAL mode: the newest visits are appended to `<db>-wal`
    /// and only periodically checkpointed into the main file. Opening the live
    /// file `immutable` (our old approach) skips the WAL entirely, so recent
    /// history was missing. Working on a private copy lets SQLite merge the WAL
    /// and avoids touching the browser's live database. Returns nil if the main
    /// file can't be read (e.g. Full Disk Access denied for Safari).
    private func openSnapshot(_ path: String) -> (db: OpaquePointer, cleanup: () -> Void)? {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
            .appendingPathComponent("beacon-history-\(UUID().uuidString)", isDirectory: true)
        guard (try? fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        let cleanup = { try? fm.removeItem(at: tmpDir) }

        let base = (path as NSString).lastPathComponent
        let destMain = tmpDir.appendingPathComponent(base)
        do {
            try fm.copyItem(at: URL(fileURLWithPath: path), to: destMain)
        } catch {
            cleanup()
            return nil   // main DB unreadable -> treat as denied/unavailable
        }
        // Sidecars are best-effort; absence just means the WAL was checkpointed.
        for suffix in ["-wal", "-shm"] {
            let src = URL(fileURLWithPath: path + suffix)
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: tmpDir.appendingPathComponent(base + suffix))
            }
        }

        var db: OpaquePointer?
        // Open read-write so SQLite can checkpoint the WAL into our copy; fall
        // back to read-only if that's refused.
        if sqlite3_open_v2(destMain.path, &db, SQLITE_OPEN_READWRITE, nil) != SQLITE_OK {
            if db != nil { sqlite3_close(db); db = nil }
            if sqlite3_open_v2(destMain.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
                if db != nil { sqlite3_close(db) }
                cleanup()
                return nil
            }
        }
        sqlite3_busy_timeout(db, 1500)
        let openedDB = db!
        return (openedDB, { sqlite3_close(openedDB); cleanup() })
    }

    /// Chromium timestamps are microseconds since 1601-01-01 UTC.
    private static func chromeDate(_ micros: Int64) -> Date {
        let secondsBetween1601And1970 = 11_644_473_600.0
        let seconds = Double(micros) / 1_000_000.0 - secondsBetween1601And1970
        return Date(timeIntervalSince1970: seconds)
    }
}
