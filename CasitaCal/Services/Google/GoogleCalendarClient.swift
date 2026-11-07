import Foundation

enum GoogleCalendarError: LocalizedError {
    case notSignedIn
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Not signed in to Google."
        case let .http(status, message): "Google Calendar error \(status): \(message)"
        }
    }
}

/// Minimal Google Calendar v3 REST client.
@MainActor
struct GoogleCalendarClient {
    let tokenProvider: () async throws -> String
    var session: URLSession = .shared

    private static let base = URL(string: "https://www.googleapis.com/calendar/v3")!

    func calendarList() async throws -> [GCalCalendar] {
        var all: [GCalCalendar] = []
        var pageToken: String?
        repeat {
            var items = [URLQueryItem(name: "minAccessRole", value: "reader")]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: GCalCalendarListResponse = try await get(path: "users/me/calendarList", query: items)
            all += page.items
            pageToken = page.nextPageToken
        } while pageToken != nil
        return all
    }

    /// Expanded (single) events overlapping [from, to).
    func events(calendarId: String, from: Date, to: Date) async throws -> [GCalEvent] {
        let iso = ISO8601DateFormatter()
        var all: [GCalEvent] = []
        var pageToken: String?
        repeat {
            var items = [
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "timeMin", value: iso.string(from: from)),
                URLQueryItem(name: "timeMax", value: iso.string(from: to)),
                URLQueryItem(name: "maxResults", value: "2500"),
            ]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: GCalEventsResponse = try await get(
                path: "calendars/\(Self.encode(calendarId))/events",
                query: items
            )
            all += page.items
            pageToken = page.nextPageToken
        } while pageToken != nil
        return all.filter { $0.status != "cancelled" }
    }

    /// Partial update of one event (or a whole series, when given the series id).
    @discardableResult
    func patchEvent(calendarId: String, eventId: String, _ patch: GCalEventPatch) async throws -> GCalEvent {
        try await send(
            "PATCH",
            path: "calendars/\(Self.encode(calendarId))/events/\(Self.encode(eventId))",
            body: try JSONEncoder().encode(patch)
        )
    }

    func event(calendarId: String, eventId: String) async throws -> GCalEvent {
        try await get(path: "calendars/\(Self.encode(calendarId))/events/\(Self.encode(eventId))", query: [])
    }

    @discardableResult
    func insertEvent(calendarId: String, _ body: GCalEventWrite) async throws -> GCalEvent {
        try await send("POST", path: "calendars/\(Self.encode(calendarId))/events", body: try JSONEncoder().encode(body))
    }

    @discardableResult
    func updateEvent(calendarId: String, eventId: String, _ body: GCalEventWrite) async throws -> GCalEvent {
        try await send(
            "PATCH",
            path: "calendars/\(Self.encode(calendarId))/events/\(Self.encode(eventId))",
            body: try JSONEncoder().encode(body)
        )
    }

    /// Google parses natural language: "Dentist Tuesday 3pm".
    func quickAdd(calendarId: String, text: String) async throws -> GCalEvent {
        try await send(
            "POST",
            path: "calendars/\(Self.encode(calendarId))/events/quickAdd",
            query: [URLQueryItem(name: "text", value: text)]
        )
    }

    func deleteEvent(calendarId: String, eventId: String) async throws {
        let _: Empty = try await send("DELETE", path: "calendars/\(Self.encode(calendarId))/events/\(Self.encode(eventId))")
    }

    private struct Empty: Decodable {}

    // MARK: - Plumbing

    private func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        try await send("GET", path: path, query: query)
    }

    private func send<T: Decodable>(_ method: String, path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> T {
        // `path` is already percent-encoded (see `encode`), so join strings rather than
        // using appendingPathComponent, which would double-encode it.
        var components = URLComponents(string: Self.base.absoluteString + "/" + path)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw GoogleCalendarError.http(status: status, message: Self.errorMessage(from: data))
        }
        if T.self == Empty.self { return Empty() as! T } // 204 No Content
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Calendar IDs contain '@' and sometimes '#', so encode as a single path segment.
    static func encode(_ id: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/#?")
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
    }

    private static func errorMessage(from data: Data) -> String {
        struct Envelope: Decodable { struct E: Decodable { var message: String }; var error: E }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error.message
            ?? String(data: data, encoding: .utf8) ?? "Unknown error"
    }
}
