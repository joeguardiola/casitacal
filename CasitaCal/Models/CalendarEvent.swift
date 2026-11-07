import Foundation

/// App-side event, parsed from Google's wire format.
struct CalendarEvent: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var title: String
    var start: Date
    /// Exclusive end. For all-day events, midnight after the last day.
    var end: Date
    var isAllDay: Bool
    var location: String?
    var notes: String?
    var colorId: String?
    /// Members explicitly tagged by CasitaCal (extendedProperties.shared).
    var taggedMemberIDs: [UUID]
    var recurringEventId: String?
    var htmlLink: String?

    static let membersPropertyKey = "casitacal_members"

    var isRecurring: Bool { recurringEventId != nil }

    /// Does this event cover any part of the given day?
    func overlaps(day: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        if start == end { return start >= dayStart && start < dayEnd } // zero-length events
        return start < dayEnd && end > dayStart
    }
}

extension CalendarEvent {
    /// Returns nil for events we can't place (missing/garbled times).
    init?(google e: GCalEvent, calendar: Calendar = .current) {
        guard let s = e.start, let en = e.end else { return nil }

        if let sd = s.date, let ed = en.date {
            guard let start = Self.parseDay(sd, calendar: calendar),
                  let end = Self.parseDay(ed, calendar: calendar) else { return nil }
            self.start = start
            self.end = max(end, start)
            self.isAllDay = true
        } else if let sdt = s.dateTime, let edt = en.dateTime {
            guard let start = Self.parseDateTime(sdt), let end = Self.parseDateTime(edt) else { return nil }
            self.start = start
            self.end = max(end, start)
            self.isAllDay = false
        } else {
            return nil
        }

        id = e.id
        title = (e.summary?.isEmpty == false ? e.summary! : "(No title)")
        location = e.location
        notes = e.description
        colorId = e.colorId
        recurringEventId = e.recurringEventId
        htmlLink = e.htmlLink
        taggedMemberIDs = (e.extendedProperties?.shared?[Self.membersPropertyKey] ?? "")
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespaces)) }
    }

    /// All-day dates are floating: "2026-11-07" means that calendar day wherever the iPad is.
    static func parseDay(_ s: String, calendar: Calendar) -> Date? {
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func parseDateTime(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
