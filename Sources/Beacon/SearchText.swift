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
    /// Lower values are better. Used to make standalone words/phrases outrank
    /// newer substring hits like "main" inside "maintain".
    enum MatchQuality: Int, Comparable {
        case exactPhrase = 0
        case wholeWords = 1
        case wordStarts = 2
        case substring = 3

        static func < (lhs: MatchQuality, rhs: MatchQuality) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Split a raw query into folded tokens on any whitespace.
    static func tokens(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map { String($0).searchFolded }
    }

    /// Classify how well a folded haystack matches folded tokens. Nil means at
    /// least one token was absent.
    static func matchQuality(_ haystack: String, tokens: [String]) -> MatchQuality? {
        guard !tokens.isEmpty else { return .substring }
        guard tokens.allSatisfy({ haystack.contains($0) }) else { return nil }

        let query = tokens.joined(separator: " ")
        if hasWholePhrase(haystack, query) { return .exactPhrase }
        if tokens.allSatisfy({ hasWholeWord(haystack, $0) }) { return .wholeWords }
        if tokens.allSatisfy({ hasWordStart(haystack, $0) }) { return .wordStarts }
        return .substring
    }

    /// True if `phrase` appears with word boundaries around the full phrase.
    /// Both strings must already be folded.
    static func hasWholePhrase(_ haystack: String, _ phrase: String) -> Bool {
        guard !phrase.isEmpty else { return false }
        var from = haystack.startIndex
        while let r = haystack.range(of: phrase, range: from..<haystack.endIndex) {
            if isBoundary(in: haystack, before: r.lowerBound)
                && isBoundary(in: haystack, after: r.upperBound) {
                return true
            }
            from = r.upperBound
        }
        return false
    }

    /// True if `token` appears as a complete word, bounded by punctuation,
    /// whitespace, path separators, or string edges. Both strings must already
    /// be folded.
    static func hasWholeWord(_ haystack: String, _ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        var from = haystack.startIndex
        while let r = haystack.range(of: token, range: from..<haystack.endIndex) {
            if isBoundary(in: haystack, before: r.lowerBound)
                && isBoundary(in: haystack, after: r.upperBound) {
                return true
            }
            from = r.upperBound
        }
        return false
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

    private static func isBoundary(in string: String, before index: String.Index) -> Bool {
        guard index > string.startIndex else { return true }
        return isBoundary(string[string.index(before: index)])
    }

    private static func isBoundary(in string: String, after index: String.Index) -> Bool {
        guard index < string.endIndex else { return true }
        return isBoundary(string[index])
    }

    private static func isBoundary(_ char: Character) -> Bool {
        !(char.isLetter || char.isNumber)
    }
}
