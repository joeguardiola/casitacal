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

    // MARK: - Plumbing

    private func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        // `path` is already percent-encoded (see `encode`), so join strings rather than
        // using appendingPathComponent, which would double-encode it.
        var components = URLComponents(string: Self.base.absoluteString + "/" + path)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw GoogleCalendarError.http(status: status, message: Self.errorMessage(from: data))
        }
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
