import Foundation
import Compression
import SQLite3

/// A single Apple Notes note pulled from the Notes database.
struct NoteRecord {
    let pk: Int64
    let title: String
    let snippet: String   // Notes' own preview text (clean, but short)
    let body: String      // full decoded text ("" if decode failed)
    let modified: Date
    let appleScriptID: String  // x-coredata:// id used to `show` the note ("" if unknown)
}

/// Reads and searches the Apple Notes database
/// (`~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite`).
///
/// Like `MessageStore`, it opens read-only and requires Full Disk Access. Note
/// bodies are stored as gzip-compressed protobuf blobs, so we decompress them
/// and extract the text heuristically (the note's title and Notes' own snippet
/// are plain columns and always available as a fallback).
final class NotesStore {
    enum State { case idle, ready, needsFullDiskAccess, unavailable }

    private(set) var state: State = .idle
    private var cache: [NoteRecord] = []

    private let dbPath = NSHomeDirectory()
        + "/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"
    private let loadCap = 100_000

    var needsFullDiskAccess: Bool { state == .needsFullDiskAccess }

    func ensureLoaded() {
        guard state == .idle else { return }
        guard FileManager.default.fileExists(atPath: dbPath) else {
            state = .unavailable
            return
        }
        load()
    }

    func retry() {
        state = .idle
        ensureLoaded()
    }

    func search(tokens: [String], limit: Int = 80) -> [NoteRecord] {
        guard state == .ready, !tokens.isEmpty else {
            Log.write("NotesStore: search skipped (state=\(state))")
            return []
        }
        var out: [NoteRecord] = []
        for rec in cache {  // newest-first
            let haystack = (rec.title + " " + (rec.body.isEmpty ? rec.snippet : rec.body)).lowercased()
            if tokens.allSatisfy({ haystack.contains($0) }) {
                out.append(rec)
                if out.count >= limit { break }
            }
        }
        Log.write("NotesStore: search tokens=\(tokens) cache=\(cache.count) matched=\(out.count)")
        return out
    }

    // MARK: - Loading

    private func load() {
        var db: OpaquePointer?
        defer { if db != nil { sqlite3_close(db) } }

        let encoded = dbPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? dbPath
        let uri = "file:\(encoded)?immutable=1"
        let openRC = sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        guard openRC == SQLITE_OK else {
            Log.write("NotesStore: open failed rc=\(openRC)")
            state = .needsFullDiskAccess
            return
        }
        sqlite3_busy_timeout(db, 1500)

        // The Core Data store UUID lets us build each note's AppleScript id
        // ("x-coredata://<uuid>/ICNote/p<pk>"), which Notes can `show` directly.
        let storeUUID = Self.scalarText(db, "SELECT Z_UUID FROM Z_METADATA LIMIT 1;") ?? ""

        // Column names carry version-specific suffixes, so resolve them defensively.
        let cols = Self.columns(db, table: "ZICCLOUDSYNCINGOBJECT")
        let titleCol = Self.pick(cols, exact: "ZTITLE1", prefix: "ZTITLE") ?? "ZTITLE1"
        let snippetCol = Self.pick(cols, exact: "ZSNIPPET", prefix: "ZSNIPPET") ?? "ZSNIPPET"
        let dateCol = Self.pick(cols, exact: "ZMODIFICATIONDATE1", prefix: "ZMODIFICATIONDATE") ?? "ZMODIFICATIONDATE1"
        let deletedClause = cols.contains("ZMARKEDFORDELETION") ? "AND (c.ZMARKEDFORDELETION IS NULL OR c.ZMARKEDFORDELETION = 0)" : ""

        let sql = """
        SELECT c.Z_PK, c.\(titleCol), c.\(snippetCol), c.\(dateCol), d.ZDATA
        FROM ZICNOTEDATA AS d
        JOIN ZICCLOUDSYNCINGOBJECT AS c ON c.Z_PK = d.ZNOTE
        WHERE d.ZDATA IS NOT NULL \(deletedClause)
        ORDER BY c.\(dateCol) DESC
        LIMIT \(loadCap);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Log.write("NotesStore: prepare failed err=\(String(cString: sqlite3_errmsg(db)))")
            state = .needsFullDiskAccess
            return
        }
        defer { sqlite3_finalize(stmt) }

        var records: [NoteRecord] = []
        var decoded = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            let pk = sqlite3_column_int64(stmt, 0)
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let snippet = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let rawDate = sqlite3_column_double(stmt, 3)

            var body = ""
            if let blob = sqlite3_column_blob(stmt, 4) {
                let len = Int(sqlite3_column_bytes(stmt, 4))
                if len > 0 {
                    let data = Data(bytes: blob, count: len)
                    if let gunzipped = Gzip.gunzip(data) {
                        body = Protobuf.extractText([UInt8](gunzipped))
                        if !body.isEmpty { decoded += 1 }
                    }
                }
            }

            let cleanTitle = title.isEmpty ? "Untitled Note" : title
            let scriptID = storeUUID.isEmpty ? "" : "x-coredata://\(storeUUID)/ICNote/p\(pk)"
            records.append(NoteRecord(pk: pk, title: cleanTitle, snippet: snippet,
                                      body: body, modified: Self.appleDate(rawDate),
                                      appleScriptID: scriptID))
        }

        cache = records
        state = .ready
        Log.write("NotesStore: loaded notes=\(records.count) bodiesDecoded=\(decoded)")
    }

    // MARK: - Helpers

    private static func scalarText(_ db: OpaquePointer?, _ sql: String) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: c)
    }

    private static func columns(_ db: OpaquePointer?, table: String) -> Set<String> {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var names = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1) { names.insert(String(cString: c)) }
        }
        return names
    }

    private static func pick(_ cols: Set<String>, exact: String, prefix: String) -> String? {
        if cols.contains(exact) { return exact }
        return cols.filter { $0.hasPrefix(prefix) }.sorted().first
    }

    private static func appleDate(_ raw: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: raw)
    }
}

// MARK: - Gzip

private enum Gzip {
    /// Decompress a gzip blob (RFC 1952) using the Compression framework.
    static func gunzip(_ data: Data) -> Data? {
        guard data.count > 18, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b else { return nil }
        let bytes = [UInt8](data)
        var idx = 10
        let flags = bytes[3]
        if flags & 0x04 != 0 {  // FEXTRA
            guard idx + 2 <= bytes.count else { return nil }
            let xlen = Int(bytes[idx]) | (Int(bytes[idx + 1]) << 8)
            idx += 2 + xlen
        }
        if flags & 0x08 != 0 {  // FNAME (NUL-terminated)
            while idx < bytes.count && bytes[idx] != 0 { idx += 1 }; idx += 1
        }
        if flags & 0x10 != 0 {  // FCOMMENT (NUL-terminated)
            while idx < bytes.count && bytes[idx] != 0 { idx += 1 }; idx += 1
        }
        if flags & 0x02 != 0 { idx += 2 }  // FHCRC
        guard idx < bytes.count - 8 else { return nil }
        let deflate = data.subdata(in: (data.startIndex + idx)..<(data.endIndex - 8))
        return rawInflate(deflate)
    }

    private static func rawInflate(_ input: Data) -> Data? {
        guard !input.isEmpty else { return nil }
        var stream = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!, dst_size: 0,
                                        src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            return nil
        }
        defer { compression_stream_destroy(&stream) }

        let bufferSize = 64 * 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dst.deallocate() }

        return input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Data? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.src_ptr = base
            stream.src_size = input.count

            var output = Data()
            let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            while true {
                stream.dst_ptr = dst
                stream.dst_size = bufferSize
                let status = compression_stream_process(&stream, flags)
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    let produced = bufferSize - stream.dst_size
                    if produced > 0 { output.append(dst, count: produced) }
                    if status == COMPRESSION_STATUS_END { return output }
                default:
                    return nil
                }
            }
        }
    }
}

// MARK: - Protobuf (minimal, text extraction only)

private enum Protobuf {
    /// Extracts the note body. Apple Notes nests the text at a stable field
    /// path: document (field 2) -> note (field 3) -> text (field 2). We follow
    /// that path for an exact result, and fall back to a "longest printable
    /// string" scan only if the structure differs.
    static func extractText(_ bytes: [UInt8]) -> String {
        if let leaf = follow(bytes, path: [2, 3, 2]),
           let text = String(bytes: leaf, encoding: .utf8), !text.isEmpty {
            return text
        }
        var best = ""
        scan(bytes, into: &best)
        // Trim any leading control bytes a heuristic match may have captured.
        return String(best.unicodeScalars.drop(while: { $0.value < 0x20 && $0 != "\n" && $0 != "\t" }))
    }

    /// Returns the payload of the length-delimited field reached by descending
    /// `path` (a list of field numbers), or nil if any hop is missing.
    private static func follow(_ bytes: [UInt8], path: [Int]) -> [UInt8]? {
        var current = bytes
        for field in path {
            guard let next = firstField(current, field: field) else { return nil }
            current = next
        }
        return current
    }

    private static func firstField(_ b: [UInt8], field: Int) -> [UInt8]? {
        var i = 0
        while i < b.count {
            guard let key = readVarint(b, &i) else { return nil }
            let fieldNumber = Int(key >> 3)
            switch key & 0x7 {
            case 0: _ = readVarint(b, &i)
            case 1: i += 8
            case 5: i += 4
            case 2:
                guard let len = readVarint(b, &i) else { return nil }
                let end = i + Int(len)
                guard end <= b.count, end >= i else { return nil }
                if fieldNumber == field { return Array(b[i..<end]) }
                i = end
            default: return nil
            }
        }
        return nil
    }

    private static func scan(_ b: [UInt8], into best: inout String) {
        var i = 0
        while i < b.count {
            guard let key = readVarint(b, &i) else { return }
            switch key & 0x7 {
            case 0:  // varint
                _ = readVarint(b, &i)
            case 1:  // 64-bit
                i += 8
            case 5:  // 32-bit
                i += 4
            case 2:  // length-delimited
                guard let len = readVarint(b, &i) else { return }
                let end = i + Int(len)
                guard end <= b.count, end >= i else { return }
                let sub = Array(b[i..<end])
                if let text = printableUTF8(sub) {
                    if text.count > best.count { best = text }
                } else {
                    scan(sub, into: &best)
                }
                i = end
            default:
                return
            }
        }
    }

    private static func readVarint(_ b: [UInt8], _ i: inout Int) -> UInt64? {
        var shift: UInt64 = 0
        var result: UInt64 = 0
        while i < b.count {
            let byte = b[i]; i += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    /// Returns the string if `bytes` is valid UTF-8 that's mostly printable
    /// (so we treat genuine text as text and binary sub-messages as messages).
    private static func printableUTF8(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 2, let s = String(bytes: bytes, encoding: .utf8) else { return nil }
        var printable = 0
        var total = 0
        for scalar in s.unicodeScalars {
            total += 1
            if scalar == "\n" || scalar == "\t" || scalar.value >= 0x20 { printable += 1 }
        }
        guard total > 0 else { return nil }
        return (Double(printable) / Double(total)) > 0.9 ? s : nil
    }
}
