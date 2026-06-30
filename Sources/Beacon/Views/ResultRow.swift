import SwiftUI

/// A single result line: file icon, name, location, and light metadata.
struct ResultRow: View {
    let result: SearchResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: result.icon)
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(result.name)
                        .font(.system(size: 13, weight: .medium))
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
                Text(subtitle)
                    .font(.system(size: 11))
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
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    /// For messages, the body snippet; for files, the containing folder.
    private var subtitle: String {
        if result.source == .message {
            return (result.messageBody ?? "").replacingOccurrences(of: "\n", with: " ")
        }
        return prettyPath(result.directory)
    }

    private var trailingDetail: String? {
        if result.source == .message {
            guard let date = result.modified else { return nil }
            return Self.relativeDate.localizedString(for: date, relativeTo: Date())
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
