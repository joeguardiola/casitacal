import SwiftUI

/// Covers the dashboard when the kiosk is idle (slideshow) or asleep (night clock).
/// Any touch returns to the dashboard (handled by KioskController's window recognizer).
struct KioskOverlay: View {
    @Environment(KioskController.self) private var kiosk

    var body: some View {
        ZStack {
            switch kiosk.mode {
            case .active:
                EmptyView()
            case .slideshow:
                SlideshowView()
                    .transition(.opacity)
            case .sleep:
                SleepClockView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: kiosk.mode)
    }
}

/// Full-screen crossfading photos with the time, weather and what's next.
struct SlideshowView: View {
    @Environment(PhotoLibrary.self) private var photos
    @Environment(EventStore.self) private var events
    @Environment(MemberStore.self) private var members

    @State private var current: UIImage?
    @State private var index = 0
    @State private var order: [String] = []
    @State private var zoom = false

    static let secondsPerPhoto: Double = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Color.black
                if let current {
                    Image(uiImage: current)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(zoom ? 1.08 : 1.0) // gentle Ken Burns
                        .clipped()
                        .id(index)
                        .transition(.opacity)
                } else {
                    emptyState
                }
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                infoPanel
                    .padding(40)
            }
            .ignoresSafeArea()
            .task(id: photos.assetIDs) {
                order = photos.assetIDs.shuffled()
                index = 0
                guard !order.isEmpty else { current = nil; return }
                let size = CGSize(width: geo.size.width * 2, height: geo.size.height * 2)
                while !Task.isCancelled {
                    let next = await photos.image(for: order[index % order.count], size: size)
                    if let next {
                        zoom = false
                        withAnimation(.easeInOut(duration: 1.2)) { current = next }
                        withAnimation(.linear(duration: Self.secondsPerPhoto + 2)) { zoom = true }
                    }
                    try? await Task.sleep(for: .seconds(Self.secondsPerPhoto))
                    index += 1
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 56))
            Text(photos.selectedAlbumId == nil ? "Choose a photo album in Photos" : "No photos in this album yet")
                .font(.title2)
        }
        .foregroundStyle(.white.opacity(0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var infoPanel: some View {
        HStack(alignment: .bottom) {
            TimelineView(.everyMinute) { ctx in
                VStack(alignment: .leading, spacing: 4) {
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.system(size: 88, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(ctx.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.title.weight(.medium))
                    if let next = nextEvent(after: ctx.date) {
                        Label {
                            Text("\(next.title) · \(next.isAllDay ? "today" : next.start.formatted(date: .omitted, time: .shortened))")
                        } icon: {
                            Image(systemName: "calendar")
                        }
                        .font(.title2.weight(.semibold))
                        .padding(.top, 6)
                    }
                }
            }
            Spacer()
            WeatherBadge(style: .large)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 8)
    }

    private func nextEvent(after now: Date) -> CalendarEvent? {
        let endOfDay = Calendar.app.date(byAdding: .day, value: 1, to: Calendar.app.startOfDay(for: now))!
        return events.events
            .filter { $0.end > now && $0.start < endOfDay }
            .filter { EventMapper.isVisible($0, members: members.members, hidden: members.hiddenMemberIDs) }
            .sorted { ($0.isAllDay ? 1 : 0, $0.start) < ($1.isAllDay ? 1 : 0, $1.start) }
            .first
    }
}

/// Night mode: near-black screen with a soft clock.
struct SleepClockView: View {
    var body: some View {
        ZStack {
            Color.black
            TimelineView(.everyMinute) { ctx in
                VStack(spacing: 6) {
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.system(size: 120, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text(ctx.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.title2)
                }
                .foregroundStyle(.white.opacity(0.35))
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
    }
}
