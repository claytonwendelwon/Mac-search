import AppKit
import Foundation
import QuickLookThumbnailing

/// Tiny async Quick Look thumbnail cache for file rows. Used by Recents and
/// file search so saved images, PDFs, and videos show an actual preview instead
/// of a generic document icon. Falls back to NSWorkspace icons when Quick Look
/// cannot produce a thumbnail.
final class ThumbnailStore: ObservableObject {
    static let shared = ThumbnailStore()

    @Published private(set) var images: [String: NSImage] = [:]
    private var inFlight = Set<String>()

    private init() {}

    func image(for result: SearchResult, size: CGSize = CGSize(width: 44, height: 44)) -> NSImage {
        guard result.source == .file else { return result.icon }
        if let image = images[result.path] { return image }
        request(path: result.path, size: size, fallback: result.icon)
        return result.icon
    }

    private func request(path: String, size: CGSize, fallback: NSImage) {
        guard !inFlight.contains(path) else { return }
        inFlight.insert(path)

        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(path)
                self.images[path] = thumbnail?.nsImage ?? fallback
            }
        }
    }
}
