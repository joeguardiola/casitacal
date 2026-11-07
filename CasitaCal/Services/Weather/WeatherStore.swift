import CoreLocation
import Foundation
import Observation
import WeatherKit

/// Current conditions + today's forecast for the header, refreshed every 30 minutes.
/// Needs the WeatherKit entitlement (paid Apple Developer team) — without it, `status` says so.
@MainActor
@Observable
final class WeatherStore {
    struct Snapshot: Equatable {
        var temperature: Measurement<UnitTemperature>
        var high: Measurement<UnitTemperature>?
        var low: Measurement<UnitTemperature>?
        var symbolName: String
        var condition: String
        var precipitationChance: Double?
        var upcoming: [Day]

        struct Day: Equatable, Identifiable {
            var date: Date
            var symbolName: String
            var high: Measurement<UnitTemperature>
            var low: Measurement<UnitTemperature>
            var precipitationChance: Double
            var id: Date { date }
        }
    }

    enum Status: Equatable {
        case idle
        case needsLocationPermission
        case locationDenied
        case unavailable(String)
        case ready
    }

    private(set) var snapshot: Snapshot?
    private(set) var status: Status = .idle
    private(set) var attribution: WeatherAttribution?
    private(set) var lastUpdated: Date?

    private let location = OneShotLocation()
    private var lastFetch: Date?

    var isEntitled: Bool {
        // Entitlement only exists in builds signed by a paid team (see Config/Base.xcconfig).
        Bundle.main.object(forInfoDictionaryKey: "CASITACAL_HAS_WEATHERKIT") as? String == "YES"
    }

    func refreshIfStale(maxAge: TimeInterval = 30 * 60) async {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < maxAge, snapshot != nil { return }
        await refresh()
    }

    func refresh() async {
        lastFetch = Date()
        guard isEntitled else {
            status = .unavailable("Weather turns on once the paid Apple Developer account is set up.")
            return
        }
        switch location.authorization {
        case .notDetermined:
            status = .needsLocationPermission
            return
        case .denied, .restricted:
            status = .locationDenied
            return
        default:
            break
        }
        guard let here = await location.current() else {
            status = .unavailable("Couldn't find the iPad's location.")
            return
        }
        do {
            let (current, daily) = try await WeatherService.shared.weather(for: here, including: .current, .daily)
            let today = daily.forecast.first
            snapshot = Snapshot(
                temperature: current.temperature,
                high: today?.highTemperature,
                low: today?.lowTemperature,
                symbolName: current.symbolName,
                condition: current.condition.description,
                precipitationChance: today?.precipitationChance,
                upcoming: daily.forecast.prefix(5).map {
                    .init(date: $0.date, symbolName: $0.symbolName, high: $0.highTemperature,
                          low: $0.lowTemperature, precipitationChance: $0.precipitationChance)
                }
            )
            if attribution == nil { attribution = try? await WeatherService.shared.attribution }
            lastUpdated = Date()
            status = .ready
        } catch {
            status = .unavailable(Self.explain(error))
        }
    }

    /// Ask for location permission (shows the system prompt once).
    func requestPermission() async {
        await location.requestPermission()
        await refresh()
    }

    private static func explain(_ error: Error) -> String {
        let text = String(describing: error)
        if text.localizedCaseInsensitiveContains("auth") || text.localizedCaseInsensitiveContains("entitlement")
            || text.localizedCaseInsensitiveContains("JWT") {
            return "Weather needs the paid Apple Developer account with WeatherKit turned on."
        }
        return "Weather unavailable right now."
    }

    /// Run until cancelled: refresh every 30 minutes.
    func keepFresh() async {
        while !Task.isCancelled {
            await refreshIfStale()
            try? await Task.sleep(for: .seconds(5 * 60))
        }
    }
}

/// Minimal async wrapper around CLLocationManager for a single fix.
@MainActor
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var authContinuation: CheckedContinuation<Void, Never>?
    private var cached: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer // weather doesn't need precision
    }

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    func requestPermission() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { c in
            authContinuation = c
            manager.requestWhenInUseAuthorization()
        }
    }

    /// The kitchen iPad doesn't move, so one fix per launch is plenty.
    func current() async -> CLLocation? {
        if let cached { return cached }
        guard locationContinuation == nil else { return nil }
        let fix = await withCheckedContinuation { c in
            locationContinuation = c
            manager.requestLocation()
        }
        cached = fix
        return fix
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in
            self.locationContinuation?.resume(returning: last)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            self.authContinuation?.resume()
            self.authContinuation = nil
        }
    }
}
