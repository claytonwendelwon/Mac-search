import Foundation
import SQLite3

/// A single iMessage/SMS row pulled from the Messages database.
struct MessageRecord {
    let rowid: Int64
    let date: Date
    let isFromMe: Bool
    let handle: String   // the other party's phone/email ("" if unknown / group)
    let chatIdentifier: String
    let chatGUID: String
    let chatName: String
    let text: String
    /// Case/diacritic-folded "text handle", precomputed once at load so each
    /// keystroke filters without re-folding the whole history.
    let folded: String

    var isGroup: Bool {
        chatGUID.contains(";+;") || chatIdentifier.lowercased().hasPrefix("chat")
    }

    /// Best available one-to-one conversation target. Sent rows often have no
    /// message.handle_id, while their joined chat still identifies the peer.
    var conversationHandle: String {
        guard !isGroup else { return "" }
        if !handle.isEmpty { return handle }
        if chatIdentifier.contains("@") || chatIdentifier.contains(where: \.isNumber) {
            return chatIdentifier
        }
        return ""
    }
}

/// Reads and searches the macOS Messages database (`~/Library/Messages/chat.db`).
///
/// The DB is opened read-only and immutable so we never lock it while Messages
/// is running. Reading it requires Full Disk Access; if that's missing, the
/// open fails and we surface `.needsFullDiskAccess` so the UI can guide the user.
///
/// Messages are loaded once into memory (most-recent first, capped) and then
/// filtered in-process on each keystroke, which keeps typing instant.
final class MessageStore {
    enum State {
        case idle
        case ready
        case needsFullDiskAccess
        case unavailable   // no Messages DB on this machine
    }

    private(set) var state: State = .idle
    private var cache: [MessageRecord] = []

    private let dbPath = NSHomeDirectory() + "/Library/Messages/chat.db"
    // Effectively "everything" - a safety ceiling so a pathological history
    // can't exhaust memory. Real histories are far below this.
    private let loadCap = 1_000_000

    var needsFullDiskAccess: Bool { state == .needsFullDiskAccess }

    /// Load the DB once. Safe to call repeatedly; only does work when idle.
    func ensureLoaded() {
        guard state == .idle else { return }
        guard FileManager.default.fileExists(atPath: dbPath) else {
            state = .unavailable
            return
        }
        load()
    }

    /// Forget any prior failure and try again (e.g. after the user grants access).
    func retry() {
        state = .idle
        ensureLoaded()
    }

    /// Search by message text, raw handle, or (when `nameResolver` is given)
    /// the resolved contact name — so typing "Mom" finds Mom's messages, not
    /// just messages containing the word. Tokens must already be folded.
    ///
    /// `isCancelled` is polled during the scan; a search that has been
    /// superseded by newer keystrokes aborts immediately instead of grinding
    /// through the rest of the history (its partial result is dropped by the
    /// caller's generation check anyway).
    func search(tokens: [String], limit: Int = 80,
                nameResolver: ((String) -> String?)? = nil,
                isCancelled: (() -> Bool)? = nil) -> [MessageRecord] {
        guard state == .ready, !tokens.isEmpty else {
            Log.write("MessageStore: search skipped (state=\(state), tokens=\(tokens))")
            return []
        }
        var out: [(record: MessageRecord, quality: SearchText.MatchQuality)] = []
        for (index, rec) in cache.enumerated() {   // already sorted newest-first
            if index & 0x3FF == 0, isCancelled?() == true {
                Log.write("MessageStore: search cancelled at row \(index) tokens=\(tokens)")
                return out.map(\.record)
            }
            // Fast path: match on the precomputed text+handle haystack first;
            // only fall back to the contact-name lookup when the text misses.
            let textQuality = SearchText.matchQuality(rec.folded, tokens: tokens)
            let nameQuality: SearchText.MatchQuality?
            if let nameResolver,
               let name = foldedName(for: rec.conversationHandle, resolve: nameResolver) {
                nameQuality = SearchText.matchQuality(name, tokens: tokens)
            } else {
                nameQuality = nil
            }
            let quality = [textQuality, nameQuality].compactMap { $0 }.min()
            if let quality {
                out.append((rec, quality))
            }
        }
        let results = out
            .sorted {
                if $0.quality != $1.quality { return $0.quality < $1.quality }
                return $0.record.date > $1.record.date
            }
            .prefix(limit)
            .map(\.record)
        Log.write("MessageStore: search tokens=\(tokens) cache=\(cache.count) matched=\(out.count) returned=\(results.count)")
        return results
    }

    /// Folded contact names, cached per handle. Only consulted once the
    /// resolver is ready, so cached values are stable. Accessed solely from the
    /// engine's serial message queue.
    private var nameCache: [String: String?] = [:]

    private func foldedName(for handle: String, resolve: (String) -> String?) -> String? {
        guard !handle.isEmpty else { return nil }
        if let cached = nameCache[handle] { return cached }
        let folded = resolve(handle)?.searchFolded
        nameCache[handle] = folded
        return folded
    }

    // MARK: - Loading

    private func load() {
        var db: OpaquePointer?
        defer { if db != nil { sqlite3_close(db) } }

        // Percent-encode the path for the file: URI; immutable=1 avoids needing
        // the -wal/-shm sidecars and any write lock.
        let encoded = dbPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? dbPath
        let uri = "file:\(encoded)?immutable=1"

        let openFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let openRC = sqlite3_open_v2(uri, &db, openFlags, nil)
        guard openRC == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "nil db"
            Log.write("MessageStore: open failed rc=\(openRC) err=\(msg)")
            // Typically "authorization denied" => Full Disk Access not granted.
            state = .needsFullDiskAccess
            return
        }
        sqlite3_busy_timeout(db, 1500)

        let chatColumns = Self.columns(db, table: "chat")
        let chatNameExpression = chatColumns.contains("display_name")
            ? "COALESCE(c.display_name, '')"
            : "''"
        let sql = """
        SELECT m.ROWID, m.date, m.is_from_me, COALESCE(h.id, ''),
               m.text, m.attributedBody,
               COALESCE(c.chat_identifier, ''), COALESCE(c.guid, ''),
               \(chatNameExpression)
        FROM message AS m
        LEFT JOIN handle AS h ON m.handle_id = h.ROWID
        LEFT JOIN chat AS c ON c.ROWID = (
            SELECT cmj.chat_id
            FROM chat_message_join AS cmj
            WHERE cmj.message_id = m.ROWID
            ORDER BY cmj.chat_id
            LIMIT 1
        )
        ORDER BY m.date DESC
        LIMIT \(loadCap);
        """

        var stmt: OpaquePointer?
        let prepRC = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepRC == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            Log.write("MessageStore: prepare failed rc=\(prepRC) err=\(msg)")
            state = .needsFullDiskAccess
            return
        }
        defer { sqlite3_finalize(stmt) }

        var records: [MessageRecord] = []
        var scanned = 0, fromTextCol = 0, fromBlob = 0, dropped = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            scanned += 1
            let rowid = sqlite3_column_int64(stmt, 0)
            let rawDate = sqlite3_column_int64(stmt, 1)
            let isFromMe = sqlite3_column_int(stmt, 2) == 1
            let handle = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            let chatIdentifier = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
            let chatGUID = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""
            let chatName = sqlite3_column_text(stmt, 8).map { String(cString: $0) } ?? ""

            var text = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            if !text.isEmpty {
                fromTextCol += 1
            } else if let blob = sqlite3_column_blob(stmt, 5) {
                let len = Int(sqlite3_column_bytes(stmt, 5))
                if len > 0 {
                    let data = Data(bytes: blob, count: len)
                    text = Self.decodeAttributedBody(data) ?? ""
                    if !text.isEmpty { fromBlob += 1 }
                }
            }
            guard !text.isEmpty else { dropped += 1; continue }

            records.append(MessageRecord(rowid: rowid,
                                         date: Self.appleDate(rawDate),
                                         isFromMe: isFromMe,
                                         handle: handle,
                                         chatIdentifier: chatIdentifier,
                                         chatGUID: chatGUID,
                                         chatName: chatName,
                                         text: text,
                                         folded: (text + " " + handle + " " + chatIdentifier
                                                  + " " + chatName).searchFolded))
        }

        cache = records
        state = .ready
        Log.write("MessageStore: loaded scanned=\(scanned) textCol=\(fromTextCol) blob=\(fromBlob) dropped=\(dropped) cache=\(records.count)")
    }

    // MARK: - Helpers

    private static func columns(_ db: OpaquePointer?, table: String) -> Set<String> {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        var names = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let value = sqlite3_column_text(stmt, 1) {
                names.insert(String(cString: value))
            }
        }
        return names
    }

    /// Messages stores dates as nanoseconds (modern) or seconds (legacy) since
    /// the 2001-01-01 reference date.
    private static func appleDate(_ raw: Int64) -> Date {
        let seconds = raw > 100_000_000_000 ? Double(raw) / 1_000_000_000.0 : Double(raw)
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// Best-effort extraction of the message text from the `attributedBody`
    /// blob (an old-style "streamtyped" archive). Newer Messages versions leave
    /// the `text` column NULL and store the body only here.
    static func decodeAttributedBody(_ data: Data) -> String? {
        guard let marker = data.range(of: Data("NSString".utf8)) else { return nil }

        // After "NSString" comes a class marker; the string value is preceded by
        // a 0x2B ('+') byte, then a variable-length count, then the UTF-8 bytes.
        var i = marker.upperBound
        let scanEnd = min(data.count, marker.upperBound + 12)
        var found = false
        while i < scanEnd {
            if data[i] == 0x2B { i += 1; found = true; break }
            i += 1
        }
        guard found, i < data.count else { return nil }

        var length = Int(data[i]); i += 1
        // 0x81/0x82 signal 2- and 3-byte little-endian lengths.
        if length == 0x81 {
            guard i + 1 < data.count else { return nil }
            length = Int(data[i]) | (Int(data[i + 1]) << 8)
            i += 2
        } else if length == 0x82 {
            guard i + 2 < data.count else { return nil }
            length = Int(data[i]) | (Int(data[i + 1]) << 8) | (Int(data[i + 2]) << 16)
            i += 3
        }
        guard length > 0, i + length <= data.count else { return nil }
        return String(data: data.subdata(in: i..<(i + length)), encoding: .utf8)
    }
}
