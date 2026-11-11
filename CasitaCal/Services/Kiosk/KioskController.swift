import Observation
import UIKit

/// Decides what the kitchen display shows when nobody is touching it:
/// the normal dashboard, a photo slideshow (idle), or the dark night clock.
///
/// The night clock shows during the scheduled sleep hours (screen dimmed), and also any time the
/// room is dark. There's no public ambient-light API, so "dark" is read from the screen brightness
/// that Auto-Brightness picks; in that case we leave brightness alone so the reading stays valid.
@MainActor
@Observable
final class KioskController {
    enum Mode: Equatable { case active, slideshow, sleep }

    private(set) var mode: Mode = .active {
        didSet { if mode != oldValue { modeChanged(from: oldValue) } }
    }
    private(set) var lastInteraction = Date()
    /// Started with the Slideshow button, so only a touch ends it (the night fallback aside).
    private var isManualSlideshow = false
    /// Bumps each time the display wakes from the slideshow or night clock (screens reset to Calendar/today).
    private(set) var wakeCount = 0

    /// Wake when someone walks up (front camera, slideshow only).
    var presenceEnabled: Bool { didSet { save(); updatePresence() } }
    @ObservationIgnored private lazy var presence = PresenceDetector { [weak self] in self?.registerInteraction() }

    // Settings (persisted).
    var slideshowAfterMinutes: Int { didSet { save() } }      // 0 = off
    var sleepEnabled: Bool { didSet { save() } }
    var sleepStart: DateComponents { didSet { save() } }      // hour/minute
    var sleepEnd: DateComponents { didSet { save() } }
    /// Brightness during sleep (0...1).
    var sleepBrightness: Double { didSet { save() } }
    /// Also show the night clock whenever the room is dark (via Auto-Brightness).
    var darkRoomEnabled: Bool { didSet { save(); evaluate() } }
    /// Screen brightness (as Auto-Brightness sets it) at or below which the room counts as dark.
    /// Built in, like the Nest Hub's low-light mode: no setup. Measured on the kitchen iPad on
    /// 2026-11-10: lights on 0.35–0.50, lights off 0.15–0.25.
    nonisolated static let darkThreshold = 0.27

    /// Latest screen brightness (what Auto-Brightness chose).
    private(set) var screenBrightness: Double = 1
    private(set) var roomIsDark = false
    /// Brightness has to rise this far above the threshold before the room counts as light again.
    /// One Auto-Brightness step: the kitchen iPad reads 0.25 dark and 0.35–0.50 with the lights on.
    nonisolated static let darkHysteresis = 0.05

    /// How long a touch keeps the screen awake during sleep hours with the lights on.
    nonisolated static let wakeDuringSleep: TimeInterval = 2 * 60
    /// In a dark room the night clock comes on this soon after the last touch.
    nonisolated static let wakeInDarkRoom: TimeInterval = 10
    /// How long a slideshow started by hand keeps running at night before the dark clock takes over.
    nonisolated static let manualSlideshowAtNight: TimeInterval = 30 * 60

    private var savedBrightness: CGFloat?
    private var isDimmed: Bool { savedBrightness != nil }
    private var recognizer: InteractionRecognizer?
    private var brightnessObserver: NSObjectProtocol?
    private let defaults = UserDefaults.standard

    init() {
        slideshowAfterMinutes = defaults.object(forKey: "kiosk.slideshowAfter") as? Int ?? 10
        sleepEnabled = defaults.object(forKey: "kiosk.sleepEnabled") as? Bool ?? true
        sleepStart = DateComponents(hour: defaults.object(forKey: "kiosk.sleepStartH") as? Int ?? 22,
                                    minute: defaults.object(forKey: "kiosk.sleepStartM") as? Int ?? 0)
        sleepEnd = DateComponents(hour: defaults.object(forKey: "kiosk.sleepEndH") as? Int ?? 6,
                                  minute: defaults.object(forKey: "kiosk.sleepEndM") as? Int ?? 30)
        sleepBrightness = defaults.object(forKey: "kiosk.sleepBrightness") as? Double ?? 0.05
        darkRoomEnabled = defaults.object(forKey: "kiosk.darkRoom") as? Bool ?? true
        defaults.removeObject(forKey: "kiosk.darkThreshold") // no longer a setting
        presenceEnabled = defaults.object(forKey: "kiosk.presence") as? Bool ?? false
    }

    private func modeChanged(from old: Mode) {
        if mode != .slideshow { isManualSlideshow = false }
        if old != .active && mode == .active { wakeCount += 1 }
        updatePresence()
    }

    private func updatePresence() {
        // Not for a manual slideshow: the person who just tapped the button is standing right at the camera.
        if presenceEnabled && mode == .slideshow && !isManualSlideshow && PresenceDetector.isAuthorized {
            presence.start()
        } else {
            presence.stop()
        }
    }

    /// Turns walk-up wake on, asking for camera access first. Returns false if access was refused.
    func enablePresence() async -> Bool {
        let granted = PresenceDetector.isAuthorized ? true : await PresenceDetector.requestAccess()
        presenceEnabled = granted
        return granted
    }

    /// Start watching touches on the app window and evaluating idle state.
    func start() async {
        installRecognizer()
        brightnessObserver = NotificationCenter.default.addObserver(
            forName: UIScreen.brightnessDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateRoomDarkness()
                self?.evaluate()
            }
        }
        while !Task.isCancelled {
            updateRoomDarkness()
            evaluate()
            try? await Task.sleep(for: .seconds(3)) // the dark-room clock should come on within ~10 s
        }
    }

    func registerInteraction() {
        lastInteraction = Date()
        isManualSlideshow = false
        if mode != .active { mode = .active }
        if isDimmed { restoreBrightness() }
    }

    /// Show the slideshow right now (the Slideshow button).
    func startSlideshowNow() {
        isManualSlideshow = true
        lastInteraction = Date()
        mode = .slideshow
    }

    func evaluate(now: Date = Date()) {
        let idle = now.timeIntervalSince(lastInteraction)
        let target = Self.mode(
            idle: idle, now: now, slideshowAfterMinutes: slideshowAfterMinutes,
            sleepEnabled: sleepEnabled, sleepStart: sleepStart, sleepEnd: sleepEnd,
            current: mode, roomIsDark: darkRoomEnabled && roomIsDark, manualSlideshow: isManualSlideshow
        )
        if target != mode { mode = target }
        // Dim only for scheduled sleep; in a dark room Auto-Brightness already has it low.
        let scheduled = sleepEnabled && Self.isWithin(now, start: sleepStart, end: sleepEnd)
        let shouldDim = target == .sleep && scheduled
        if shouldDim && !isDimmed { dim() } else if !shouldDim && isDimmed { restoreBrightness() }
    }

    /// Reads the screen brightness as a light sensor (skipped while we've dimmed it ourselves).
    private func updateRoomDarkness() {
        guard !isDimmed, let screen else { return }
        screenBrightness = Double(screen.brightness)
        roomIsDark = Self.isDark(brightness: screenBrightness, threshold: Self.darkThreshold, wasDark: roomIsDark)
    }

    nonisolated static func isDark(brightness: Double, threshold: Double, wasDark: Bool) -> Bool {
        wasDark ? brightness < threshold + darkHysteresis : brightness <= threshold
    }

    /// Pure decision logic (unit-tested).
    nonisolated static func mode(
        idle: TimeInterval, now: Date, slideshowAfterMinutes: Int, sleepEnabled: Bool,
        sleepStart: DateComponents, sleepEnd: DateComponents, current: Mode, roomIsDark: Bool = false,
        manualSlideshow: Bool = false, calendar: Calendar = .current
    ) -> Mode {
        let scheduled = sleepEnabled && isWithin(now, start: sleepStart, end: sleepEnd, calendar: calendar)
        let isNight = scheduled || roomIsDark
        if manualSlideshow && current == .slideshow && (!isNight || idle < manualSlideshowAtNight) {
            return .slideshow
        }
        if isNight {
            return idle >= (roomIsDark ? wakeInDarkRoom : wakeDuringSleep) ? .sleep : .active
        }
        if current == .slideshow { return .slideshow } // started manually or by idle; a touch ends it
        if slideshowAfterMinutes > 0 && idle >= TimeInterval(slideshowAfterMinutes * 60) { return .slideshow }
        return .active
    }

    /// Is `date`'s time-of-day inside [start, end)? Handles windows that cross midnight.
    nonisolated static func isWithin(_ date: Date, start: DateComponents, end: DateComponents, calendar: Calendar = .current) -> Bool {
        let t = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let s = (start.hour ?? 0) * 60 + (start.minute ?? 0)
        let e = (end.hour ?? 0) * 60 + (end.minute ?? 0)
        if s == e { return false }
        return s < e ? (t >= s && t < e) : (t >= s || t < e)
    }

    // MARK: Brightness

    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)?.screen
    }

    private func dim() {
        guard let screen else { return }
        if savedBrightness == nil { savedBrightness = screen.brightness }
        screen.brightness = CGFloat(sleepBrightness)
    }

    private func restoreBrightness() {
        guard let screen, let savedBrightness else { return }
        screen.brightness = savedBrightness
        self.savedBrightness = nil
    }

    // MARK: Touch tracking

    private func installRecognizer() {
        guard recognizer == nil else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        guard let window else { return }
        let r = InteractionRecognizer { [weak self] in self?.registerInteraction() }
        window.addGestureRecognizer(r)
        recognizer = r
    }

    private func save() {
        defaults.set(slideshowAfterMinutes, forKey: "kiosk.slideshowAfter")
        defaults.set(sleepEnabled, forKey: "kiosk.sleepEnabled")
        defaults.set(sleepStart.hour, forKey: "kiosk.sleepStartH")
        defaults.set(sleepStart.minute, forKey: "kiosk.sleepStartM")
        defaults.set(sleepEnd.hour, forKey: "kiosk.sleepEndH")
        defaults.set(sleepEnd.minute, forKey: "kiosk.sleepEndM")
        defaults.set(sleepBrightness, forKey: "kiosk.sleepBrightness")
        defaults.set(darkRoomEnabled, forKey: "kiosk.darkRoom")
        defaults.set(presenceEnabled, forKey: "kiosk.presence")
    }
}

/// Sees every touch in the window without interfering with buttons, scrolling or sheets.
final class InteractionRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let onTouch: @MainActor () -> Void

    init(onTouch: @escaping @MainActor () -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch()
        state = .failed // never "recognize"; just observe
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
