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
