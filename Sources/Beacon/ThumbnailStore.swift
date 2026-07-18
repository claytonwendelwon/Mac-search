import AppKit
import Foundation
import QuickLookThumbnailing

/// Tiny async Quick Look thumbnail cache for file rows. Used by Recents and
/// file search so saved images, PDFs, and videos show an actual preview instead
/// of a generic document icon. Falls back to NSWorkspace icons when Quick Look
/// cannot produce a thumbnail.
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private struct PendingRequest {
        let path: String
        let size: CGSize
        let key: String
        let fallback: NSImage
    }

    private let images = NSCache<NSString, NSImage>()
    private var inFlight = Set<String>()
    private var completions: [String: [(NSImage) -> Void]] = [:]
    private var requests: [String: QLThumbnailGenerator.Request] = [:]
    /// Overflow queue, drained newest-first (LIFO): the most recent requests
    /// are the rows currently on screen, so they must win over rows the user
    /// already scrolled past. A dictionary here drained in arbitrary order,
    /// which made grids fill in scattered and slow.
    private var pending: [PendingRequest] = []
    private var pendingKeys = Set<String>()

    private init() {
        images.countLimit = 600
        images.totalCostLimit = 48 * 1_024 * 1_024
    }

    func image(for result: SearchResult,
               size: CGSize = CGSize(width: 44, height: 44),
               completion: ((NSImage) -> Void)? = nil) -> NSImage {
        guard result.source == .file else { return result.icon }
        let key = cacheKey(path: result.path, size: size)
        if let image = images.object(forKey: key as NSString) { return image }
        if let completion {
            completions[key, default: []].append(completion)
        }
        request(path: result.path, size: size, key: key, fallback: result.icon)
        return result.icon
    }

    func cancelAll() {
        for request in requests.values {
            QLThumbnailGenerator.shared.cancel(request)
        }
        requests.removeAll()
        pending.removeAll()
        pendingKeys.removeAll()
        inFlight.removeAll()
        completions.removeAll()
    }

    private func request(path: String, size: CGSize, key: String,
                         fallback: NSImage) {
        guard !inFlight.contains(key), !pendingKeys.contains(key) else { return }
        guard inFlight.count < 12 else {
            pending.append(PendingRequest(
                path: path, size: size, key: key, fallback: fallback
            ))
            pendingKeys.insert(key)
            // A fast scroll can queue hundreds of rows; drop the oldest —
            // they're offscreen and will re-request on appear if needed.
            if pending.count > 400 {
                let dropped = pending.removeFirst()
                pendingKeys.remove(dropped.key)
                completions.removeValue(forKey: dropped.key)
            }
            return
        }
        inFlight.insert(key)

        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        requests[key] = request

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.requests.removeValue(forKey: key) != nil else { return }
                self.inFlight.remove(key)
                let image = thumbnail?.nsImage ?? fallback
                let cost = max(1, Int(size.width * size.height * 4))
                self.images.setObject(image, forKey: key as NSString, cost: cost)
                let callbacks = self.completions.removeValue(forKey: key) ?? []
                callbacks.forEach { $0(image) }
                self.startPendingRequests()
            }
        }
    }

    private func startPendingRequests() {
        while inFlight.count < 12, let next = pending.popLast() {
            pendingKeys.remove(next.key)
            request(
                path: next.path,
                size: next.size,
                key: next.key,
                fallback: next.fallback
            )
        }
    }

    private func cacheKey(path: String, size: CGSize) -> String {
        "\(path)|\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }
}
