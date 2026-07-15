import SwiftUI

struct GridResultCard: View {
    enum Style: Equatable {
        case app
        case image
    }

    let result: SearchResult
    let isSelected: Bool
    let style: Style

    @State private var loadedThumbnail: NSImage?
    @State private var loadedThumbnailID: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: style == .app ? 8 : 7) {
            visual
            VStack(spacing: 2) {
                Text(result.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(style == .app ? 12 : 8)
        .frame(maxWidth: .infinity)
        .frame(height: style == .app ? 126 : 142)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.17 : 0.11)
                        : Color.primary.opacity(colorScheme == .dark ? 0.025 : 0.018)
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onAppear { loadThumbnail() }
        .onChange(of: result.id) { _ in
            loadedThumbnail = nil
            loadedThumbnailID = nil
            loadThumbnail()
        }
    }

    @ViewBuilder
    private var visual: some View {
        if style == .app {
            Image(nsImage: result.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 58, height: 58)
        } else {
            Image(nsImage: loadedThumbnail ?? result.icon)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func loadThumbnail() {
        guard style == .image else { return }
        let resultID = result.id
        loadedThumbnailID = resultID
        loadedThumbnail = ThumbnailStore.shared.image(
            for: result,
            size: CGSize(width: 160, height: 92)
        ) { image in
            if loadedThumbnailID == resultID {
                loadedThumbnail = image
            }
        }
    }

    private var detail: String {
        if style == .app {
            let directory = result.directory
            if directory == "/Applications" { return "Applications" }
            if directory == NSHomeDirectory() + "/Applications" { return "~/Applications" }
            return (directory as NSString).lastPathComponent
        }
        return result.kind.isEmpty ? result.url.pathExtension.uppercased() : result.kind
    }
}
