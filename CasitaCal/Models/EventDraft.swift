import Foundation

enum RepeatRule: String, CaseIterable, Identifiable, Sendable {
    case never, daily, weekdays, weekly, biweekly, monthly, yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: "Never"
        case .daily: "Every day"
        case .weekdays: "Every weekday (Mon–Fri)"
        case .weekly: "Every week"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Every month"
        case .yearly: "Every year"
        }
    }

    /// RFC 5545 rule Google expects in `recurrence`.
    var rrule: String? {
        switch self {
        case .never: nil
        case .daily: "RRULE:FREQ=DAILY"
        case .weekdays: "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
        case .weekly: "RRULE:FREQ=WEEKLY"
        case .biweekly: "RRULE:FREQ=WEEKLY;INTERVAL=2"
        case .monthly: "RRULE:FREQ=MONTHLY"
        case .yearly: "RRULE:FREQ=YEARLY"
        }
    }
}

/// Editable copy of an event (new or existing).
struct EventDraft: Equatable {
    var title = ""
    var isAllDay = false
    var start: Date
    var end: Date
    var repeatRule: RepeatRule = .never
    var people: [Member.ID] = []
    var location = ""
    var notes = ""

    /// New event on `day`: next whole hour if today, otherwise 9 AM; one hour long.
    init(day: Date, calendar: Calendar = .app) {
        let base: Date
        if calendar.isDateInToday(day) {
            let nextHour = calendar.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? .now
            base = nextHour
        } else {
            base = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }
        start = base
        end = base.addingTimeInterval(3600)
    }

    init(event: CalendarEvent, people: [Member.ID], calendar: Calendar = .app) {
        title = event.title == "(No title)" ? "" : event.title
        isAllDay = event.isAllDay
        start = event.start
        // All-day ends are exclusive in Google; the editor shows the last day.
        end = event.isAllDay ? (calendar.date(byAdding: .day, value: -1, to: event.end) ?? event.start) : event.end
        self.people = people
        location = event.location ?? ""
        notes = event.notes ?? ""
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && end >= start
    }

    /// Wire body for insert/patch.
    /// - Parameter includeRecurrence: only for new events (series rules are edited in Google).
    func body(members: [Member], includeRecurrence: Bool, calendar: Calendar = .app) -> GCalEventWrite {
        let chosen = people.compactMap { id in members.first { $0.id == id } }
        let tz = calendar.timeZone.identifier
        let startTime: GCalEventTime
        let endTime: GCalEventTime
        if isAllDay {
            let lastDay = max(calendar.startOfDay(for: end), calendar.startOfDay(for: start))
            let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: lastDay)!
            startTime = GCalEventTime(date: Self.dayString(start, calendar: calendar))
            endTime = GCalEventTime(date: Self.dayString(exclusiveEnd, calendar: calendar))
        } else {
            startTime = GCalEventTime(dateTime: Self.rfc3339(start, calendar: calendar), timeZone: tz)
            endTime = GCalEventTime(dateTime: Self.rfc3339(max(end, start), calendar: calendar), timeZone: tz)
        }
        return GCalEventWrite(
            summary: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: notes,
            location: location,
            start: startTime,
            end: endTime,
            recurrence: includeRecurrence ? repeatRule.rrule.map { [$0] } : nil,
            colorId: chosen.first?.color.googleColorId,
            membersTag: chosen.count > 1 ? chosen.map(\.id.uuidString).joined(separator: ",") : ""
        )
    }

    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func rfc3339(_ date: Date, calendar: Calendar) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = calendar.timeZone
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
