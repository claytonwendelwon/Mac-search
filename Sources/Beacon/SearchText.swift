import Foundation

/// Canonical text folding used for all in-memory matching (Messages, Notes,
/// Clipboard, History, and file ranking), so every source matches the same way
/// Spotlight's `CONTAINS[cd]` does for files: case-, diacritic-, and
/// width-insensitive ("jose" finds "José").
extension String {
    var searchFolded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current)
    }
}

enum SearchText {
    /// Split a raw query into folded tokens on any whitespace.
    static func tokens(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map { String($0).searchFolded }
    }

    /// True if `token` appears at the start of a word in `haystack` — either at
    /// the very beginning, or right after a non-alphanumeric character
    /// ("state" matches "Chase Statement.pdf" and "chase-statement.pdf").
    /// Both strings must already be folded.
    static func hasWordStart(_ haystack: String, _ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        var from = haystack.startIndex
        while let r = haystack.range(of: token, range: from..<haystack.endIndex) {
            if r.lowerBound == haystack.startIndex { return true }
            let prev = haystack[haystack.index(before: r.lowerBound)]
            if !(prev.isLetter || prev.isNumber) { return true }
            from = r.upperBound
        }
        return false
    }
}
