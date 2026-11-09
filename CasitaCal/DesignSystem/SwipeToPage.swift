import SwiftUI
import UIKit

/// Decides whether a finished drag counts as a page turn (pure, unit-tested).
enum SwipePaging {
    enum Direction: Equatable { case previous, next }

    static let distance: CGFloat = 60
    static let flickDistance: CGFloat = 30
    static let flickSpeed: CGFloat = 450

    static func direction(translation: CGSize, velocity: CGSize) -> Direction? {
        let dx = translation.width
        guard abs(dx) > abs(translation.height) else { return nil }
        guard abs(dx) >= distance || (abs(dx) >= flickDistance && abs(velocity.width) >= flickSpeed) else { return nil }
        return dx < 0 ? .next : .previous
    }
}

/// A horizontal-only pan that runs alongside vertical ScrollViews, so columns keep scrolling.
private struct HorizontalSwipe: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    var onSwipe: (SwipePaging.Direction) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: nil)
            return abs(v.x) > abs(v.y) * 1.5
        }

        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.isEnabled = isEnabled
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard recognizer.state == .ended else { return }
        let t = recognizer.translation(in: nil), v = recognizer.velocity(in: nil)
        let direction = SwipePaging.direction(
            translation: CGSize(width: t.x, height: t.y),
            velocity: CGSize(width: v.x, height: v.y)
        )
        if let direction { onSwipe(direction) }
    }
}

extension View {
    /// Swipe left for `next`, right for `previous`. The arrows stay for VoiceOver and precision.
    func swipeToPage(
        isEnabled: Bool = true,
        previous: @escaping () -> Void,
        next: @escaping () -> Void
    ) -> some View {
        contentShape(Rectangle())
            .gesture(HorizontalSwipe(isEnabled: isEnabled) { $0 == .next ? next() : previous() })
    }
}

/// Keeps a rolling view on today as the date changes on an always-on screen.
/// A view paged somewhere else stays where it is.
struct FollowsToday: ViewModifier {
    @Binding var anchor: Date
    @State private var knownToday = Date()
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in roll() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { roll() } }
    }

    private func roll() {
        let now = Date()
        guard !Calendar.app.isDate(knownToday, inSameDayAs: now) else { return }
        anchor = CalendarRanges.rolledAnchor(anchor, previousToday: knownToday, now: now)
        knownToday = now
    }
}

/// Slides new content in from `edge` whenever `key` changes.
struct PagedContent<Key: Hashable, Content: View>: View {
    let key: Key
    let edge: Edge
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            content
                .id(key)
                .transition(.push(from: edge))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}
