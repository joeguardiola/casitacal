import Foundation

// Wire formats for the Google Calendar v3 REST API (only the fields we use).

struct GCalCalendarListResponse: Decodable {
    var items: [GCalCalendar]
    var nextPageToken: String?
}

struct GCalCalendar: Decodable, Identifiable, Hashable {
    var id: String
    var summary: String
    var summaryOverride: String?
    var backgroundColor: String?
    var primary: Bool?
    var accessRole: String

    var displayName: String { summaryOverride ?? summary }
    var canWrite: Bool { accessRole == "owner" || accessRole == "writer" }
}

struct GCalEventsResponse: Decodable {
    var items: [GCalEvent]
    var nextPageToken: String?
    var timeZone: String?
}

struct GCalEvent: Codable, Equatable {
    var id: String
    var status: String?
    var summary: String?
    var description: String?
    var location: String?
    var colorId: String?
    var start: GCalEventTime?
    var end: GCalEventTime?
    var recurringEventId: String?
    var htmlLink: String?
    var extendedProperties: ExtendedProperties?

    struct ExtendedProperties: Codable, Equatable {
        var shared: [String: String]?
        var `private`: [String: String]?
    }
}

/// Either `date` (all-day, "yyyy-MM-dd") or `dateTime` (RFC 3339).
struct GCalEventTime: Codable, Equatable {
    var date: String?
    var dateTime: String?
    var timeZone: String?
}

/// Body for assigning people to an event.
/// `colorId: nil` is sent as JSON null, which resets the event to the calendar's color.
struct GCalEventPatch: Encodable {
    var colorId: String?
    var sharedProperties: [String: String]

    enum CodingKeys: String, CodingKey { case colorId, extendedProperties }
    enum ExtendedKeys: String, CodingKey { case shared }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(colorId, forKey: .colorId) // explicit null clears it
        var ext = c.nestedContainer(keyedBy: ExtendedKeys.self, forKey: .extendedProperties)
        try ext.encode(sharedProperties, forKey: .shared)
    }
}
