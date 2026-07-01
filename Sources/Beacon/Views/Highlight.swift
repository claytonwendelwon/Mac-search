import SwiftUI

/// Text helpers for search results: building an `AttributedString` that bolds
/// the matched query tokens, and trimming a long message to a window centered
/// on the first match so the matched word is actually visible.
enum Highlight {
    /// Returns `text` with every (case-insensitive) occurrence of any token
    /// rendered in `strong`, and everything else in `base`.
    static func attributed(_ text: String, tokens: [String],
                           base: Font, strong: Font) -> AttributedString {
        let ranges = matchRanges(in: text, tokens: tokens)
        guard !ranges.isEmpty else {
            var plain = AttributedString(text)
            plain.font = base
            return plain
        }

        var result = AttributedString()
        var cursor = text.startIndex
        for range in ranges {
            if cursor < range.lowerBound {
                var seg = AttributedString(String(text[cursor..<range.lowerBound]))
                seg.font = base
                result += seg
            }
            var hit = AttributedString(String(text[range]))
            hit.font = strong
            result += hit
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            var seg = AttributedString(String(text[cursor..<text.endIndex]))
            seg.font = base
            result += seg
        }
        return result
    }

    /// Trims `text` to ~`maxLength` characters, starting a bit before the first
    /// matched token so the match is visible. Adds leading/trailing ellipses.
    static func snippet(_ text: String, tokens: [String],
                        maxLength: Int = 140, lead: Int = 24) -> String {
        let collapsed = text.replacingOccurrences(of: "\n", with: " ")
        guard collapsed.count > maxLength else { return collapsed }

        let chars = Array(collapsed)
        let firstMatch = tokens
            .compactMap { token -> Int? in
                guard !token.isEmpty,
                      let r = collapsed.range(of: token,
                                              options: [.caseInsensitive, .diacriticInsensitive])
                else { return nil }
                return collapsed.distance(from: collapsed.startIndex, to: r.lowerBound)
            }
            .min()

        let start = max(0, (firstMatch ?? 0) - lead)
        let end = min(chars.count, start + maxLength)
        var out = String(chars[start..<end])
        if start > 0 { out = "\u{2026}" + out }
        if end < chars.count { out += "\u{2026}" }
        return out
    }

    private static func matchRanges(in text: String, tokens: [String]) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        for token in tokens where !token.isEmpty {
            var start = text.startIndex
            while let r = text.range(of: token,
                                     options: [.caseInsensitive, .diacriticInsensitive],
                                     range: start..<text.endIndex) {
                ranges.append(r)
                start = r.upperBound
            }
        }
        guard !ranges.isEmpty else { return [] }

        ranges.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for r in ranges {
            if let last = merged.last, r.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                merged.append(r)
            }
        }
        return merged
    }
}
