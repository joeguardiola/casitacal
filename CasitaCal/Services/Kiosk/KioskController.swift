import Observation
import UIKit

/// Decides what the kitchen display shows when nobody is touching it:
/// the normal dashboard, a photo slideshow (idle), or a dim night clock (sleep hours).
@MainActor
@Observable
final class KioskController {
    enum Mode: Equatable { case active, slideshow, sleep }

    private(set) var mode: Mode = .active
    private(set) var lastInteraction = Date()

    // Settings (persisted).
    var slideshowAfterMinutes: Int { didSet { save() } }      // 0 = off
    var sleepEnabled: Bool { didSet { save() } }
    var sleepStart: DateComponents { didSet { save() } }      // hour/minute
    var sleepEnd: DateComponents { didSet { save() } }
    /// Brightness during sleep (0...1).
    var sleepBrightness: Double { didSet { save() } }

    /// How long a touch keeps the screen awake during sleep hours.
    nonisolated static let wakeDuringSleep: TimeInterval = 2 * 60

    private var savedBrightness: CGFloat?
    private var recognizer: InteractionRecognizer?
    private let defaults = UserDefaults.standard

    init() {
        slideshowAfterMinutes = defaults.object(forKey: "kiosk.slideshowAfter") as? Int ?? 10
        sleepEnabled = defaults.object(forKey: "kiosk.sleepEnabled") as? Bool ?? true
        sleepStart = DateComponents(hour: defaults.object(forKey: "kiosk.sleepStartH") as? Int ?? 22,
                                    minute: defaults.object(forKey: "kiosk.sleepStartM") as? Int ?? 0)
        sleepEnd = DateComponents(hour: defaults.object(forKey: "kiosk.sleepEndH") as? Int ?? 6,
                                  minute: defaults.object(forKey: "kiosk.sleepEndM") as? Int ?? 30)
        sleepBrightness = defaults.object(forKey: "kiosk.sleepBrightness") as? Double ?? 0.05
    }

    /// Start watching touches on the app window and evaluating idle state.
    func start() async {
        installRecognizer()
        while !Task.isCancelled {
            evaluate()
            try? await Task.sleep(for: .seconds(10))
        }
    }

    func registerInteraction() {
        lastInteraction = Date()
        if mode != .active { setMode(.active) }
    }

    /// Show the slideshow right now (from the Photos screen).
    func startSlideshowNow() {
        setMode(.slideshow)
    }

    func evaluate(now: Date = Date()) {
        let idle = now.timeIntervalSince(lastInteraction)
        let target = Self.mode(
            idle: idle, now: now, slideshowAfterMinutes: slideshowAfterMinutes,
            sleepEnabled: sleepEnabled, sleepStart: sleepStart, sleepEnd: sleepEnd,
            current: mode
        )
        if target != mode { setMode(target) }
    }

    /// Pure decision logic (unit-tested).
    nonisolated static func mode(
        idle: TimeInterval, now: Date, slideshowAfterMinutes: Int, sleepEnabled: Bool,
        sleepStart: DateComponents, sleepEnd: DateComponents, current: Mode, calendar: Calendar = .current
    ) -> Mode {
        if sleepEnabled && isWithin(now, start: sleepStart, end: sleepEnd, calendar: calendar) {
            return idle >= wakeDuringSleep ? .sleep : .active
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

    private func setMode(_ new: Mode) {
        let old = mode
        mode = new
        if new == .sleep { dim() } else if old == .sleep { restoreBrightness() }
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
