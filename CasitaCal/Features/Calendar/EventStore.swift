import Foundation
import Observation

/// Loads events for the visible date range from the family Google Calendar
/// and keeps them fresh while the app is on screen.
@MainActor
@Observable
final class EventStore {
    private(set) var calendars: [GCalCalendar] = []
    private(set) var events: [CalendarEvent] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var lastSynced: Date?

    var selectedCalendarId: String? {
        didSet {
            defaults.set(selectedCalendarId, forKey: Self.calendarKey)
            events = []
            loadedRange = nil
        }
    }

    var selectedCalendar: GCalCalendar? { calendars.first { $0.id == selectedCalendarId } }

    private(set) var loadedRange: DateInterval?
    private let auth: GoogleAuth
    private let defaults: UserDefaults
    private static let calendarKey = "casitacal.familyCalendarId"
    private var client: GoogleCalendarClient {
        GoogleCalendarClient(tokenProvider: { [auth] in try await auth.accessToken() })
    }

    init(auth: GoogleAuth, defaults: UserDefaults = .standard) {
        self.auth = auth
        self.defaults = defaults
        self.selectedCalendarId = defaults.string(forKey: Self.calendarKey)
    }

    func loadCalendars() async {
        guard auth.isSignedIn else { return }
        do {
            calendars = try await client.calendarList()
                .sorted { ($0.primary == true ? 0 : 1, $0.displayName) < ($1.primary == true ? 0 : 1, $1.displayName) }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Fetch events for `range`. Safe to call repeatedly (polling).
    func load(_ range: DateInterval) async {
        guard auth.isSignedIn, let calendarId = selectedCalendarId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let raw = try await client.events(calendarId: calendarId, from: range.start, to: range.end)
            // The calendar or range may have changed while we were waiting.
            guard calendarId == selectedCalendarId else { return }
            events = raw.compactMap { CalendarEvent(google: $0) }
                .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
            loadedRange = range
            lastSynced = Date()
            lastError = nil
        } catch is CancellationError {
            // View went away mid-request.
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Reload `range` now and then every `interval` seconds until the task is cancelled.
    func keepFresh(_ range: DateInterval, every interval: Duration = .seconds(60)) async {
        while !Task.isCancelled {
            await load(range)
            try? await Task.sleep(for: interval)
        }
    }

    /// Assign people to an event and save it to Google.
    ///
    /// One person: just the event color (so a phone can change it later).
    /// Several people: first person's color + CasitaCal's hidden tag listing everyone.
    /// Nobody: calendar color, tag cleared.
    func assign(_ event: CalendarEvent, to people: [Member], allRepeats: Bool) async throws {
        guard let calendarId = selectedCalendarId else { return }
        let targetId = allRepeats ? (event.recurringEventId ?? event.id) : event.id
        let colorId = people.first?.color.googleColorId
        let tag = people.count > 1 ? people.map(\.id.uuidString).joined(separator: ",") : ""
        let patch = GCalEventPatch(colorId: colorId, sharedProperties: [CalendarEvent.membersPropertyKey: tag])

        try await client.patchEvent(calendarId: calendarId, eventId: targetId, patch)

        // Show the change right away, then confirm with a fresh load.
        let tagIDs = people.count > 1 ? people.map(\.id) : []
        for i in events.indices where events[i].id == event.id || (allRepeats && events[i].recurringEventId == targetId) {
            events[i].colorId = colorId
            events[i].taggedMemberIDs = tagIDs
        }
        if let loadedRange { await load(loadedRange) }
    }

    func reset() {
        calendars = []
        events = []
        loadedRange = nil
        lastSynced = nil
    }
}
