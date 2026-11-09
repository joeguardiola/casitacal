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

    /// Short form for narrow cards: "4–5p", "9:30–10a", "11a–1p". 24-hour locales stay 24-hour.
    func compactTimeText(calendar: Calendar = .current, locale: Locale = .current) -> String {
        if isAllDay { return "All day" }
        let parts = { (d: Date) in (calendar.component(.hour, from: d), calendar.component(.minute, from: d)) }
        let (sh, sm) = parts(start), (eh, em) = parts(end)

        if locale.hourCycle == .oneToTwentyFour || locale.hourCycle == .zeroToTwentyThree {
            let f = { (h: Int, m: Int) in String(format: "%02d:%02d", h, m) }
            return start == end ? f(sh, sm) : "\(f(sh, sm))–\(f(eh, em))"
        }
        let f = { (h: Int, m: Int) -> String in
            let h12 = h % 12 == 0 ? 12 : h % 12
            return m == 0 ? "\(h12)" : String(format: "%d:%02d", h12, m)
        }
        let meridiem = { (h: Int) in h < 12 ? "a" : "p" }
        if start == end { return f(sh, sm) + meridiem(sh) }
        let startSuffix = meridiem(sh) == meridiem(eh) ? "" : meridiem(sh)
        return "\(f(sh, sm))\(startSuffix)–\(f(eh, em))\(meridiem(eh))"
    }

    /// Just the start, short: "4p", "9:30a". For chips with room for little else.
    func compactStartText(calendar: Calendar = .current, locale: Locale = .current) -> String {
        var point = self
        point.end = start
        return point.compactTimeText(calendar: calendar, locale: locale)
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

/// Card used in Week and Schedule.
struct EventCard: View {
    enum Size { case compact, regular, large }

    let event: CalendarEvent
    let style: EventStyle
    var size: Size = .regular

    var body: some View {
        if size == .compact { compactBody } else { fullBody }
    }

    /// Narrow columns: as much of the width as possible goes to the title.
    private var compactBody: some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(style.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(titleFont)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
                HStack(spacing: 4) {
                    Text(event.compactTimeText())
                        .font(detailFont)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if !style.members.isEmpty {
                        MemberDots(members: style.members, size: 18)
                    }
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.softColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var fullBody: some View {
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
