import Foundation

final class SearchGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func set(_ newValue: Int) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func isCurrent(_ candidate: Int) -> Bool {
        current == candidate
    }
}

enum PageWindow {
    static func slice<T>(_ rows: [T], limit: Int) -> (rows: [T], hasMore: Bool) {
        (Array(rows.prefix(limit)), rows.count > limit)
    }
}

enum SearchPerformancePolicy {
    static let pageSize = 160
    static let initialMetadataFetch = 640
    static let maximumMetadataFetch = 10_000

    static func metadataReadLimit(pageLimit: Int,
                                  previousLimit: Int) -> Int {
        min(
            maximumMetadataFetch,
            max(initialMetadataFetch, max(previousLimit * 2, pageLimit + 1))
        )
    }
}
