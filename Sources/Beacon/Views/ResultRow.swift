import SwiftUI

/// A single result line: file icon, name, location, and light metadata.
struct ResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    var tokens: [String] = []
    /// In the Recents view, show *when* the file was last used instead of
    /// kind/size - recency is the whole point there.
    var showRecency: Bool = false
    @ObservedObject private var thumbnails = ThumbnailStore.shared
    @ObservedObject private var favicons = FaviconStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            thumbnailView

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(titleText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if result.source == .file && result.matchKind == .content {
                        Label("text match", systemImage: "text.magnifyingglass")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                Text(subtitleText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            if let detail = trailingDetail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected
                      ? Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.11)
                      : Color.clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var thumbnailView: some View {
        let isFile = result.source == .file
        let isHistory = result.source == .history
        let image = isFile ? thumbnails.image(for: result)
            : isHistory ? favicons.image(for: result)
            : result.icon
        let isPreview = isFile || isHistory
        return Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: isPreview ? .fill : .fit)
            .frame(width: isPreview ? 38 : 30, height: isPreview ? 38 : 30)
            .clipShape(RoundedRectangle(cornerRadius: isPreview ? 8 : 0, style: .continuous))
    }

    /// Title with matched tokens bolded. The contact/file name is the title.
    private var titleText: AttributedString {
        Highlight.attributed(result.name, tokens: tokens,
                             base: .system(size: 13, weight: .medium),
                             strong: .system(size: 13, weight: .bold))
    }

    /// For messages/notes: a window of the body centered on the match (with a
    /// "You:" prefix for sent messages), matched words bolded. For files: folder.
    private var subtitleText: AttributedString {
        if result.source == .clipboard {
            let body = Highlight.snippet(result.messageBody ?? "", tokens: tokens)
            let app = (result.kind.isEmpty || result.kind == "Clipboard") ? "" : "\(result.kind) · "
            return Highlight.attributed(app + body, tokens: tokens,
                                        base: .system(size: 11),
                                        strong: .system(size: 11, weight: .semibold))
        }
        if result.source == .history {
            let url = Highlight.snippet(result.messageBody ?? "", tokens: tokens, maxLength: 90)
            let prefix = result.kind.isEmpty ? "" : "\(result.kind) · "
            return Highlight.attributed(prefix + url, tokens: tokens,
                                        base: .system(size: 11),
                                        strong: .system(size: 11, weight: .semibold))
        }
        if result.source == .settings {
            return Highlight.attributed(result.messageBody ?? "System Settings", tokens: tokens,
                                        base: .system(size: 11),
                                        strong: .system(size: 11, weight: .semibold))
        }
        if result.source == .mail {
            let body = Highlight.snippet(result.messageBody ?? "", tokens: tokens)
            let sender = result.kind.isEmpty ? "" : "\(result.kind) · "
            return Highlight.attributed(sender + body, tokens: tokens,
                                        base: .system(size: 11),
                                        strong: .system(size: 11, weight: .semibold))
        }
        if result.source == .calendar {
            let details = Highlight.snippet(result.messageBody ?? "", tokens: tokens)
            let calendar = result.kind.isEmpty ? "" : "\(result.kind) · "
            return Highlight.attributed(calendar + details, tokens: tokens,
                                        base: .system(size: 11),
                                        strong: .system(size: 11, weight: .semibold))
        }
        if result.source == .message || result.source == .note {
            let body = Highlight.snippet(result.messageBody ?? "", tokens: tokens)
            let text = (result.source == .message && result.messageFromMe) ? "You: \(body)" : body
            return Highlight.attributed(text, tokens: tokens,
                                        base: .system(size: 11),
                                        strong: .system(size: 11, weight: .semibold))
        }
        var plain = AttributedString(prettyPath(result.directory))
        plain.font = .system(size: 11)
        return plain
    }

    private var trailingDetail: String? {
        if result.source == .message || result.source == .note
            || result.source == .mail || result.source == .clipboard
            || result.source == .history || result.source == .calendar {
            guard let date = result.modified else { return nil }
            return Self.relativeDate.localizedString(for: date, relativeTo: Date())
        }
        if showRecency, result.effectiveRecency != .distantPast {
            return Self.relativeDate.localizedString(for: result.effectiveRecency, relativeTo: Date())
        }
        var parts: [String] = []
        if !result.kind.isEmpty { parts.append(result.kind) }
        if let size = result.size, size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    private static let relativeDate: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func prettyPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
