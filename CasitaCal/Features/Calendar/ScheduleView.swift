import SwiftUI

/// Agenda list: the next 30 days, days without events skipped (except today).
struct ScheduleView: View {
    let days: [Date]
    let events: [CalendarEvent]
    let members: [Member]
    var onSelect: (CalendarEvent) -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let groups = days.compactMap { day -> (Date, [CalendarEvent])? in
            let items = DayLayout.agenda(events, on: day)
            return items.isEmpty && !Calendar.current.isDateInToday(day) ? nil : (day, items)
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(groups, id: \.0) { day, items in
                    HStack(alignment: .top, spacing: sizeClass == .compact ? 10 : 24) {
                        dayBadge(day)
                        VStack(spacing: 10) {
                            if items.isEmpty {
                                Text("Nothing scheduled")
                                    .font(.title3)
                                    .foregroundStyle(Palette.inkSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 14)
                            }
                            ForEach(items) { e in
                                EventCard(event: e, style: EventStyle(e, members: members), size: sizeClass == .compact ? .regular : .large)
                                    .onTapGesture { onSelect(e) }
                            }
                        }
                    }
                }
                if groups.allSatisfy({ $0.1.isEmpty }) {
                    Text("No events in the next \(CalendarRanges.scheduleDays) days.")
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func dayBadge(_ day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        return VStack(spacing: 0) {
            Text(day, format: .dateTime.weekday(.abbreviated))
                .font(.headline)
                .foregroundStyle(isToday ? Palette.accent : Palette.inkSecondary)
            Text(day, format: .dateTime.day())
                .font(.system(size: sizeClass == .compact ? 28 : 38, weight: .bold, design: .rounded))
                .foregroundStyle(isToday ? Palette.accent : Palette.ink)
            Text(day, format: .dateTime.month(.abbreviated))
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(width: sizeClass == .compact ? 52 : 80)
    }
}
