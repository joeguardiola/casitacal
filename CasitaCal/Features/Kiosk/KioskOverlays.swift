import CoreImage
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

    @State private var current: SlideshowFrame?
    @State private var index = 0
    @State private var order: [String] = []
    @State private var zoom = false

    static let secondsPerPhoto: Double = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Color.black
                if let current {
                    SlideshowPhoto(frame: current, screen: geo.size, zoom: zoom)
                        .id(current.id)
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
                        let backdrop = await SlideshowFit.backdrop(of: next)
                        zoom = false
                        withAnimation(.easeInOut(duration: 1.2)) {
                            current = SlideshowFrame(photo: next, backdrop: backdrop)
                        }
                        withAnimation(.linear(duration: Self.secondsPerPhoto + 2)) { zoom = true }
                    }
                    try? await Task.sleep(for: .seconds(Self.secondsPerPhoto))
                    index += 1
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .onAppear { if photos.canRead { photos.reload() } }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 56))
            Text(photos.selectedAlbumId == nil ? "Choose a photo album in Settings" : "No photos in this album yet")
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
                    TonightDinnerCard(style: .slideshow)
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

private struct SlideshowFrame: Identifiable {
    let id = UUID()
    let photo: UIImage
    let backdrop: UIImage?
}

/// One slide. Photos close to the screen's shape fill it; anything else is shown whole over a blurred
/// copy of itself, so a portrait photo on a landscape iPad keeps everyone's heads.
private struct SlideshowPhoto: View {
    let frame: SlideshowFrame
    let screen: CGSize
    let zoom: Bool

    var body: some View {
        if SlideshowFit.fillsScreen(photo: frame.photo.size, screen: screen) {
            filled(frame.photo, zoomedTo: 1.04)
        } else {
            ZStack {
                filled(frame.backdrop ?? frame.photo, zoomedTo: 1.08)
                    .overlay(Color.black.opacity(0.2))
                Image(uiImage: frame.photo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: screen.width, height: screen.height)
                    .shadow(color: .black.opacity(0.35), radius: 24)
            }
        }
    }

    private func filled(_ image: UIImage, zoomedTo amount: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: screen.width, height: screen.height)
            .scaleEffect(zoom ? amount : 1) // gentle Ken Burns
            .clipped()
    }
}

enum SlideshowFit {
    /// True when filling the screen would trim only a sliver of the photo.
    static func fillsScreen(photo: CGSize, screen: CGSize) -> Bool {
        guard photo.width > 0, photo.height > 0, screen.width > 0, screen.height > 0 else { return true }
        let photoShape = photo.width / photo.height
        let screenShape = screen.width / screen.height
        return min(photoShape, screenShape) / max(photoShape, screenShape) >= 0.88
    }

    /// A small, already-blurred copy, cheap enough to crossfade and zoom on an older iPad.
    static func backdrop(of photo: UIImage) async -> UIImage? {
        await Task.detached(priority: .utility) { makeBackdrop(photo) }.value
    }

    private static func makeBackdrop(_ photo: UIImage) -> UIImage? {
        guard photo.size.width > 0 else { return nil }
        let width: CGFloat = 240
        let size = CGSize(width: width, height: (photo.size.height * width / photo.size.width).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            photo.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let input = CIImage(image: small), let blur = CIFilter(name: "CIGaussianBlur") else { return small }
        blur.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(8.0, forKey: kCIInputRadiusKey)
        guard let output = blur.outputImage?.cropped(to: input.extent),
              let rendered = CIContext().createCGImage(output, from: input.extent) else { return small }
        return UIImage(cgImage: rendered)
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
