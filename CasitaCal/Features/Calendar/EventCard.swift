import SwiftUI

/// Resolves an event's people and color once, for any view.
struct EventStyle {
    let members: [Member]
    var color: Color { members.first?.color.strong ?? Palette.family }
    var softColor: Color { color.opacity(0.17) }

    init(_ event: CalendarEvent, members all: [Member]) {
        members = EventMapper.members(for: event, from: all)
    }
}

extension CalendarEvent {
    func timeText(on day: Date? = nil, calendar: Calendar = .current) -> String {
        if isAllDay { return "All day" }
        let s = start.formatted(date: .omitted, time: .shortened)
        let e = end.formatted(date: .omitted, time: .shortened)
        return start == end ? s : "\(s) – \(e)"
    }

    var startText: String {
        isAllDay ? "All day" : start.formatted(date: .omitted, time: .shortened)
    }
}

/// Tiny stacked avatars for an event's people.
struct MemberDots: View {
    let members: [Member]
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(members) { m in
                Text(m.emoji.isEmpty ? m.initial : m.emoji)
                    .font(.system(size: size * 0.55))
                    .frame(width: size, height: size)
                    .background(Circle().fill(Palette.surface))
                    .overlay(Circle().strokeBorder(m.color.strong, lineWidth: 1.5))
            }
        }
    }
}

/// Card used in Week, Schedule and the all-day strips.
struct EventCard: View {
    enum Size { case compact, regular, large }

    let event: CalendarEvent
    let style: EventStyle
    var size: Size = .regular

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(style.color)
                .frame(width: 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(titleFont)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(size == .large ? 3 : 2)
                HStack(spacing: 6) {
                    Text(event.timeText())
                    if size == .large, let location = event.location, !location.isEmpty {
                        Text("·")
                        Text(location).lineLimit(1)
                    }
                }
                .font(detailFont)
                .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 0)
            if !style.members.isEmpty {
                MemberDots(members: style.members, size: size == .large ? 28 : 20)
            }
        }
        .padding(.vertical, size == .compact ? 8 : 11)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.softColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var titleFont: Font {
        switch size {
        case .compact: .subheadline.weight(.semibold)
        case .regular: .body.weight(.semibold)
        case .large: .title3.weight(.semibold)
        }
    }

    private var detailFont: Font {
        size == .large ? .body : .footnote
    }
}

/// Block drawn inside a time grid (Day view).
struct TimeBlock: View {
    let positioned: PositionedEvent
    let style: EventStyle
    let height: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(style.color)
                .frame(width: 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(positioned.event.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(height > 60 ? 3 : 1)
                if height > 40 {
                    Text(positioned.event.timeText())
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if height > 40, !style.members.isEmpty {
                MemberDots(members: style.members, size: 20)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(style.softColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }
}
