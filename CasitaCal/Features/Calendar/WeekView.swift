import SwiftUI

/// Seven columns of stacked event cards — Skylight's readable-across-the-room week.
struct WeekView: View {
    let days: [Date]
    let events: [CalendarEvent]
    let members: [Member]
    var onSelect: (CalendarEvent) -> Void
    var onOpenDay: (Date) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(days, id: \.self) { day in
                column(day)
            }
        }
    }

    private func column(_ day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let dayEvents = DayLayout.agenda(events, on: day)
        return VStack(spacing: 10) {
            Button { onOpenDay(day) } label: {
                VStack(spacing: 2) {
                    Text(day, format: .dateTime.weekday(.abbreviated))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isToday ? Palette.accent : Palette.inkSecondary)
                    Text(day, format: .dateTime.day())
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(isToday ? .white : Palette.ink)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(isToday ? Palette.accent : .clear))
                }
            }
            .buttonStyle(.plain)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(dayEvents) { e in
                        EventCard(event: e, style: EventStyle(e, members: members), size: .compact)
                            .onTapGesture { onSelect(e) }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isToday ? Palette.accent.opacity(0.5) : Palette.hairline, lineWidth: isToday ? 2 : 1)
            )
            .opacity(day < Calendar.current.startOfDay(for: .now) ? 0.6 : 1)
        }
    }
}
