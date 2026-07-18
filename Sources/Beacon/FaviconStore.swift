import AppKit
import Foundation

/// Async, in-memory favicon loader for browser-history rows.
///
/// Intentionally avoids third-party favicon services: when a row is visible, we
/// ask that same site directly (common favicon paths, then root HTML icon
/// links) and fall back to the generic globe if nothing decodes.
final class FaviconStore {
    static let shared = FaviconStore()

    private let images = NSCache<NSString, NSImage>()
    private var inFlight = Set<String>()
    private var misses = Set<String>()
    private var completions: [String: [(NSImage) -> Void]] = [:]
    private var tasks: [String: URLSessionDataTask] = [:]
    private var pending: [String: URL] = [:]
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
        images.countLimit = 400
        images.totalCostLimit = 16 * 1_024 * 1_024
    }

    func image(for result: SearchResult,
               completion: ((NSImage) -> Void)? = nil) -> NSImage {
        guard result.source == .history, let pageURL = URL(string: result.path),
              let host = normalizedHost(pageURL.host) else {
            return result.icon
        }
        if let image = images.object(forKey: host as NSString) { return image }
        if !misses.contains(host) {
            if let completion {
                completions[host, default: []].append(completion)
            }
            request(host: host, pageURL: pageURL)
        }
        return result.icon
    }

    private func request(host: String, pageURL: URL) {
        guard !inFlight.contains(host), pending[host] == nil else { return }
        guard inFlight.count < 8 else {
            pending[host] = pageURL
            return
        }
        inFlight.insert(host)

        loadCandidates(for: host, pageURL: pageURL) { [weak self] image in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.inFlight.contains(host) else { return }
                self.inFlight.remove(host)
                self.tasks.removeValue(forKey: host)
                if let image {
                    self.images.setObject(image, forKey: host as NSString)
                    let callbacks = self.completions.removeValue(forKey: host) ?? []
                    callbacks.forEach { $0(image) }
                } else {
                    self.misses.insert(host)
                    self.completions.removeValue(forKey: host)
                }
                self.startPendingRequests()
            }
        }
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        pending.removeAll()
        inFlight.removeAll()
        completions.removeAll()
    }

    private func startPendingRequests() {
        while inFlight.count < 8, let next = pending.first {
            pending.removeValue(forKey: next.key)
            request(host: next.key, pageURL: next.value)
        }
    }

    private func loadCandidates(for host: String, pageURL: URL, completion: @escaping (NSImage?) -> Void) {
        let hosts = host.hasPrefix("www.") ? [host, String(host.dropFirst(4))] : [host, "www.\(host)"]
        let paths = ["/favicon.ico", "/favicon.png", "/apple-touch-icon.png", "/apple-touch-icon-precomposed.png"]
        let urls = hosts.flatMap { h in
            paths.compactMap { URL(string: "https://\(h)\($0)") }
        }
        load(urls: urls, host: host) { [weak self] image in
            if let image {
                completion(image)
            } else {
                self?.loadFromHTML(host: host, pageURL: pageURL,
                                   completion: completion)
            }
        }
    }

    private func load(urls: [URL], host: String,
                      completion: @escaping (NSImage?) -> Void) {
        var remaining = urls[...]

        func next() {
            guard inFlight.contains(host) else { return }
            guard let url = remaining.popFirst() else {
                completion(nil)
                return
            }
            let task = session.dataTask(with: url) { data, _, _ in
                if let image = data.flatMap(NSImage.init(data:)) {
                    completion(image)
                } else {
                    DispatchQueue.main.async { next() }
                }
            }
            tasks[host] = task
            task.resume()
        }
        next()
    }

    private func loadFromHTML(host: String, pageURL: URL,
                              completion: @escaping (NSImage?) -> Void) {
        guard let root = URL(string: "\(pageURL.scheme ?? "https")://\(pageURL.host ?? "")/") else {
            completion(nil)
            return
        }
        let task = session.dataTask(with: root) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                completion(nil)
                return
            }
            let urls = self.iconHrefs(in: html, base: root)
            DispatchQueue.main.async {
                self.load(urls: urls, host: host, completion: completion)
            }
        }
        tasks[host] = task
        task.resume()
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
