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
        cache = nil
        lastTokens = []
        lastMatches = []
    }

    func search(tokens: [String], limit: Int = 80,
                isCancelled: (() -> Bool)? = nil) -> [CalendarRecord] {
        guard permissionState == .granted else { return [] }
        if tokens == lastTokens, !lastMatches.isEmpty {
            return Array(lastMatches.prefix(limit))
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
        lastTokens = tokens
        lastMatches = ranked
        return Array(ranked.prefix(limit))
    }

    private func loadEvents() -> [CalendarRecord] {
        if let cache { return cache }
        let start = Calendar.current.date(byAdding: .year, value: -10, to: Date())!
        let end = Calendar.current.date(byAdding: .year, value: 5, to: Date())!
        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: nil
        )
        let records = eventStore.events(matching: predicate).map { event in
            let title = event.title?.isEmpty == false ? event.title! : "(Untitled Event)"
            let location = event.location ?? ""
            let notes = event.notes ?? ""
            let identifier = "\(event.calendarItemIdentifier):\(event.startDate.timeIntervalSince1970)"
            return CalendarRecord(
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
            )
        }
        cache = records
        Log.write("CalendarStore: loaded events=\(records.count)")
        return records
    }

    private static func recencyScore(_ record: CalendarRecord) -> TimeInterval {
        abs(record.start.timeIntervalSinceNow)
    }
}
