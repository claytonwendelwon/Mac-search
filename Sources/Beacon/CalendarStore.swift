import EventKit
import Foundation

enum CalendarPermissionState: Equatable {
    case notDetermined
    case granted
    case denied
}

struct CalendarRecord {
    let identifier: String
    let title: String
    let calendarName: String
    let location: String
    let notes: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let folded: String
}

/// EventKit-backed, read-only calendar search. EventKit owns account syncing;
/// Beacon only caches lightweight event metadata locally in memory.
final class CalendarStore {
    private let eventStore = EKEventStore()
    /// Guards cache/lastTokens/lastMatches: search() runs on the engine's
    /// calendar queue while refresh() is called from the main thread.
    private let lock = NSLock()
    private var cache: [CalendarRecord]?
    private var lastTokens: [String] = []
    private var lastMatches: [CalendarRecord] = []

    var permissionState: CalendarPermissionState {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        } else {
            switch status {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        }
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { granted, _ in completion(granted) }
        } else {
            eventStore.requestAccess(to: .event) { granted, _ in completion(granted) }
        }
    }

    func refresh() {
        lock.lock()
        defer { lock.unlock() }
        cache = nil
        lastTokens = []
        lastMatches = []
    }

    func search(tokens: [String], limit: Int = 80,
                isCancelled: (() -> Bool)? = nil) -> [CalendarRecord] {
        guard permissionState == .granted else { return [] }
        lock.lock()
        let cachedMatches = (tokens == lastTokens && !lastMatches.isEmpty)
            ? lastMatches : nil
        lock.unlock()
        if let cachedMatches {
            return Array(cachedMatches.prefix(limit))
        }
        let records = loadEvents()

        var matches: [(CalendarRecord, SearchText.MatchQuality)] = []
        for (index, record) in records.enumerated() {
            if index & 0xFF == 0, isCancelled?() == true { return [] }
            if tokens.isEmpty {
                matches.append((record, .exactPhrase))
            } else if let quality = SearchText.matchQuality(record.folded, tokens: tokens) {
                matches.append((record, quality))
            }
        }

        let ranked = matches.sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return Self.recencyScore($0.0) < Self.recencyScore($1.0)
        }.map(\.0)
        lock.lock()
        lastTokens = tokens
        lastMatches = ranked
        lock.unlock()
        return Array(ranked.prefix(limit))
    }

    private func loadEvents() -> [CalendarRecord] {
        lock.lock()
        if let cache {
            lock.unlock()
            return cache
        }
        lock.unlock()

        // EventKit silently clips event predicates to ~4 years (measured from
        // the start date), so a single -10y..+5y query returns only the oldest
        // slice and no recent or upcoming events. Query in 3-year windows and
        // dedupe occurrences that straddle window edges.
        let calendar = Calendar.current
        let now = Date()
        var records: [CalendarRecord] = []
        var seen = Set<String>()
        for offset in stride(from: -10, through: 4, by: 3) {
            guard let start = calendar.date(byAdding: .year, value: offset, to: now),
                  let end = calendar.date(
                      byAdding: .year, value: min(offset + 3, 5), to: now
                  ) else { continue }
            let predicate = eventStore.predicateForEvents(
                withStart: start,
                end: end,
                calendars: nil
            )
            for event in eventStore.events(matching: predicate) {
                let identifier = "\(event.calendarItemIdentifier):"
                    + "\(event.startDate.timeIntervalSince1970)"
                guard seen.insert(identifier).inserted else { continue }
                let title = event.title?.isEmpty == false
                    ? event.title! : "(Untitled Event)"
                let location = event.location ?? ""
                let notes = event.notes ?? ""
                records.append(CalendarRecord(
                    identifier: identifier,
                    title: title,
                    calendarName: event.calendar.title,
                    location: location,
                    notes: notes,
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    folded: [title, event.calendar.title, location, notes]
                        .joined(separator: " ").searchFolded
                ))
            }
        }
        lock.lock()
        cache = records
        lock.unlock()
        Log.write("CalendarStore: loaded events=\(records.count)")
        return records
    }

    private static func recencyScore(_ record: CalendarRecord) -> TimeInterval {
        abs(record.start.timeIntervalSinceNow)
    }
}
