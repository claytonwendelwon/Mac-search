import AppKit
import Foundation

/// Async, in-memory favicon loader for browser-history rows.
///
/// Intentionally avoids third-party favicon services: when a row is visible, we
/// ask that same site directly (common favicon paths, then root HTML icon
/// links) and fall back to the generic globe if nothing decodes.
final class FaviconStore: ObservableObject {
    static let shared = FaviconStore()

    @Published private(set) var images: [String: NSImage] = [:]
    private var inFlight = Set<String>()
    private var misses = Set<String>()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
    }

    func image(for result: SearchResult) -> NSImage {
        guard result.source == .history, let pageURL = URL(string: result.path),
              let host = normalizedHost(pageURL.host) else {
            return result.icon
        }
        if let image = images[host] { return image }
        if !misses.contains(host) { request(host: host, pageURL: pageURL) }
        return result.icon
    }

    private func request(host: String, pageURL: URL) {
        guard !inFlight.contains(host) else { return }
        inFlight.insert(host)

        loadCandidates(for: host, pageURL: pageURL) { [weak self] image in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(host)
                if let image {
                    self.images[host] = image
                } else {
                    self.misses.insert(host)
                }
            }
        }
    }

    private func loadCandidates(for host: String, pageURL: URL, completion: @escaping (NSImage?) -> Void) {
        let hosts = host.hasPrefix("www.") ? [host, String(host.dropFirst(4))] : [host, "www.\(host)"]
        let paths = ["/favicon.ico", "/favicon.png", "/apple-touch-icon.png", "/apple-touch-icon-precomposed.png"]
        let urls = hosts.flatMap { h in
            paths.compactMap { URL(string: "https://\(h)\($0)") }
        }
        load(urls: urls) { [weak self] image in
            if let image {
                completion(image)
            } else {
                self?.loadFromHTML(pageURL: pageURL, completion: completion)
            }
        }
    }

    private func load(urls: [URL], completion: @escaping (NSImage?) -> Void) {
        var remaining = urls[...]

        func next() {
            guard let url = remaining.popFirst() else {
                completion(nil)
                return
            }
            session.dataTask(with: url) { data, _, _ in
                if let image = data.flatMap(NSImage.init(data:)) {
                    completion(image)
                } else {
                    next()
                }
            }.resume()
        }
        next()
    }

    private func loadFromHTML(pageURL: URL, completion: @escaping (NSImage?) -> Void) {
        guard let root = URL(string: "\(pageURL.scheme ?? "https")://\(pageURL.host ?? "")/") else {
            completion(nil)
            return
        }
        session.dataTask(with: root) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                completion(nil)
                return
            }
            let urls = self.iconHrefs(in: html, base: root)
            self.load(urls: urls, completion: completion)
        }.resume()
    }

    private func iconHrefs(in html: String, base: URL) -> [URL] {
        let pattern = #"<link[^>]+rel=["'][^"']*(?:icon|apple-touch-icon)[^"']*["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
            .compactMap { match -> URL? in
                let tag = ns.substring(with: match.range)
                guard let href = href(in: tag) else { return nil }
                return URL(string: href, relativeTo: base)?.absoluteURL
            }
    }

    private func href(in tag: String) -> String? {
        let pattern = #"href=["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private func normalizedHost(_ maybeHost: String?) -> String? {
        guard let host = maybeHost?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
