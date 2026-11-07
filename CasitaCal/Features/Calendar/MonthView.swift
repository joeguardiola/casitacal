import SwiftUI

struct MonthView: View {
    let anchor: Date
    let days: [Date]
    let events: [CalendarEvent]
    let members: [Member]
    var onOpenDay: (Date) -> Void

    private let maxChips = 3

    var body: some View {
        let rows = days.count / 7
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(days.prefix(7), id: \.self) { d in
                    Text(d, format: .dateTime.weekday(.abbreviated))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(0..<rows, id: \.self) { r in
                    GridRow {
                        ForEach(days[(r * 7)..<(r * 7 + 7)], id: \.self) { day in
                            cell(day)
                        }
                    }
                }
            }
        }
    }

    private func cell(_ day: Date) -> some View {
        let cal = Calendar.current
        let inMonth = cal.isDate(day, equalTo: anchor, toGranularity: .month)
        let isToday = cal.isDateInToday(day)
        let dayEvents = DayLayout.agenda(events, on: day)

        return Button { onOpenDay(day) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(day, format: .dateTime.day())
                    .font(.headline)
                    .foregroundStyle(isToday ? .white : (inMonth ? Palette.ink : Palette.inkSecondary))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isToday ? Palette.accent : .clear))
                ForEach(dayEvents.prefix(maxChips)) { e in
                    chip(e)
                }
                if dayEvents.count > maxChips {
                    Text("+\(dayEvents.count - maxChips) more")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.leading, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.surface.opacity(inMonth ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isToday ? Palette.accent.opacity(0.5) : Palette.hairline, lineWidth: isToday ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chip(_ e: CalendarEvent) -> some View {
        let style = EventStyle(e, members: members)
        return HStack(spacing: 5) {
            Circle().fill(style.color).frame(width: 8, height: 8)
            Text(e.isAllDay ? e.title : "\(e.start.formatted(.dateTime.hour().minute())) \(e.title)")
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(e.isAllDay ? style.softColor : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}
