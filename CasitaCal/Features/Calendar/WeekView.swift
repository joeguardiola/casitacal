import SwiftUI

/// Rolling columns of stacked event cards, today on the left. Tap a day's header to widen it.
struct WeekView: View {
    let days: [Date]
    let events: [CalendarEvent]
    let members: [Member]
    var onSelect: (CalendarEvent) -> Void

    @State private var widenedDay: Date?

    private let spacing: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let widened = widenedDay.flatMap(days.firstIndex(of:))
            let widths = WeekColumns.widths(total: geo.size.width, spacing: spacing, count: days.count, widened: widened)
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    WeekDayColumn(
                        day: day,
                        events: DayLayout.agenda(events, on: day),
                        members: members,
                        isWidened: index == widened,
                        onToggleWidth: {
                            withAnimation(.snappy) { widenedDay = widenedDay == day ? nil : day }
                        },
                        onSelect: onSelect
                    )
                    .frame(width: widths[index])
                }
            }
        }
    }
}

private struct WeekDayColumn: View {
    let day: Date
    let events: [CalendarEvent]
    let members: [Member]
    let isWidened: Bool
    var onToggleWidth: () -> Void
    var onSelect: (CalendarEvent) -> Void

    @State private var hasMoreBelow = false

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    var body: some View {
        VStack(spacing: 6) {
            header
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(events) { e in
                        EventCard(event: e, style: EventStyle(e, members: members), size: .compact)
                            .onTapGesture { onSelect(e) }
                    }
                }
                .padding(5)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentSize.height - geo.visibleRect.maxY > 6
            } action: { _, more in
                withAnimation(.easeOut(duration: 0.15)) { hasMoreBelow = more }
            }
            .overlay(alignment: .bottom) {
                if hasMoreBelow { moreBelowHint }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(isToday ? Palette.accent.opacity(0.5) : Palette.hairline, lineWidth: isToday ? 2 : 1))
            .opacity(day < Calendar.current.startOfDay(for: .now) ? 0.6 : 1)
        }
    }

    /// One compact line instead of the old two-line header: more room for events.
    private var header: some View {
        Button(action: onToggleWidth) {
            HStack(spacing: 6) {
                Group {
                    if isToday {
                        Text("Today")
                    } else {
                        Text(day, format: .dateTime.weekday(isWidened ? .wide : .abbreviated))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isToday ? Palette.accent : Palette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Text(day, format: .dateTime.day())
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(isToday ? .white : Palette.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isToday ? Palette.accent : .clear))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityHint(isWidened ? "Return to equal columns" : "Make this day wider")
    }

    /// Fade and chevron at the bottom of a column while more events are below. Doesn't block touches.
    private var moreBelowHint: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Palette.surface.opacity(0), Palette.surface], startPoint: .top, endPoint: .bottom)
                .frame(height: 44)
            Image(systemName: "chevron.compact.down")
                .font(.title2.weight(.bold))
                .foregroundStyle(Palette.accent)
                .padding(.bottom, 4)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transition(.opacity)
    }
}
