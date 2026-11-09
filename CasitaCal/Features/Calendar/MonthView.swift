import SwiftUI

struct MonthView: View {
    let anchor: Date
    let days: [Date]
    let events: [CalendarEvent]
    let members: [Member]
    var onOpenDay: (Date) -> Void

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
            GeometryReader { geo in
                let rowHeight = MonthCells.rowHeight(total: geo.size.height, rows: rows, spacing: 6)
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(0..<rows, id: \.self) { r in
                        GridRow {
                            ForEach(days[(r * 7)..<(r * 7 + 7)], id: \.self) { day in
                                cell(day, rowHeight: rowHeight)
                            }
                        }
                    }
                }
            }
        }
    }

    private func cell(_ day: Date, rowHeight: CGFloat) -> some View {
        let cal = Calendar.current
        let inMonth = cal.isDate(day, equalTo: anchor, toGranularity: .month)
        let isToday = cal.isDateInToday(day)
        let dayEvents = DayLayout.agenda(events, on: day)
        let shown = MonthCells.chipCount(rowHeight: rowHeight)
        let hidden = max(dayEvents.count - shown, 0)

        return Button { onOpenDay(day) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(day, format: .dateTime.day())
                        .font(.headline)
                        .foregroundStyle(isToday ? .white : (inMonth ? Palette.ink : Palette.inkSecondary))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(isToday ? Palette.accent : .clear))
                    Spacer(minLength: 0)
                    if hidden > 0 {
                        Text("+\(hidden)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.trailing, 4)
                            .accessibilityLabel("\(hidden) more")
                    }
                }
                ForEach(dayEvents.prefix(shown)) { e in
                    chip(e)
                }
                Spacer(minLength: 0)
            }
            .padding(5)
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight, alignment: .topLeading)
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
            Text(e.isAllDay ? e.title : "\(e.compactStartText()) \(e.title)")
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
