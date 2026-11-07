import SwiftUI

/// Time grid for one day, optionally split into a column per person (Skylight style).
struct DayView: View {
    let day: Date
    let events: [CalendarEvent]
    let members: [Member]
    @Binding var byPerson: Bool
    var onSelect: (CalendarEvent) -> Void

    private let hourHeight: CGFloat = 64
    private let rulerWidth: CGFloat = 64

    private struct Lane: Identifiable {
        let id: String
        let title: String
        let member: Member?
        let events: [CalendarEvent]
    }

    private var lanes: [Lane] {
        guard byPerson else {
            return [Lane(id: "all", title: "", member: nil, events: events)]
        }
        var result = members.map { m in
            Lane(id: m.id.uuidString, title: m.name, member: m,
                 events: events.filter { EventMapper.members(for: $0, from: members).contains(m) })
        }
        let everyone = events.filter { EventMapper.members(for: $0, from: members).isEmpty }
        result.insert(Lane(id: "family", title: "Everyone", member: nil, events: everyone), at: 0)
        return result
    }

    var body: some View {
        let lanes = lanes
        VStack(spacing: 10) {
            if byPerson { laneHeaders(lanes) }
            allDayRow(lanes)
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 8) {
                        ruler
                        ForEach(lanes) { lane in
                            laneGrid(lane)
                        }
                    }
                    .overlay(alignment: .topLeading) { nowLine }
                    .padding(.bottom, 24)
                }
                .onAppear { proxy.scrollTo(initialHour, anchor: .top) }
                .onChange(of: day) { proxy.scrollTo(initialHour, anchor: .top) }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var initialHour: Int {
        Calendar.current.isDateInToday(day) ? max(Calendar.current.component(.hour, from: .now) - 1, 0) : 7
    }

    private func laneHeaders(_ lanes: [Lane]) -> some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: rulerWidth, height: 1)
            ForEach(lanes) { lane in
                HStack(spacing: 8) {
                    if let m = lane.member {
                        ProfileAvatar(member: m, size: 32)
                    } else {
                        Image(systemName: "person.3.fill")
                            .foregroundStyle(Palette.family)
                            .frame(width: 32, height: 32)
                    }
                    Text(lane.title).font(.headline).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func allDayRow(_ lanes: [Lane]) -> some View {
        let hasAny = lanes.contains { !DayLayout.allDay($0.events, on: day).isEmpty }
        if hasAny {
            HStack(alignment: .top, spacing: 8) {
                Text("All day")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: rulerWidth, alignment: .trailing)
                    .padding(.top, 10)
                ForEach(lanes) { lane in
                    VStack(spacing: 6) {
                        ForEach(DayLayout.allDay(lane.events, on: day)) { e in
                            EventCard(event: e, style: EventStyle(e, members: members), size: .compact)
                                .onTapGesture { onSelect(e) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
    }

    private var ruler: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hourLabel(hour))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: rulerWidth - 8, height: hourHeight, alignment: .topTrailing)
                    .offset(y: -7)
                    .id(hour)
            }
        }
        .padding(.leading, 8)
    }

    private func laneGrid(_ lane: Lane) -> some View {
        let positioned = DayLayout.timed(lane.events, on: day)
        let dayStart = Calendar.current.startOfDay(for: day)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { _ in
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                    Spacer().frame(height: hourHeight - 1)
                }
            }
            GeometryReader { geo in
                ForEach(positioned) { p in
                    let top = p.start.timeIntervalSince(dayStart) / 3600 * hourHeight
                    let visualEnd = max(p.end, p.start.addingTimeInterval(DayLayout.minimumDuration))
                    let height = max(visualEnd.timeIntervalSince(p.start) / 3600 * hourHeight - 2, 22)
                    let width = geo.size.width / CGFloat(p.columnCount)
                    TimeBlock(positioned: p, style: EventStyle(p.event, members: members), height: height)
                        .frame(width: width - 3, height: height)
                        .offset(x: CGFloat(p.column) * width, y: top + 1)
                        .onTapGesture { onSelect(p.event) }
                }
            }
        }
        .frame(height: hourHeight * 24)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var nowLine: some View {
        if Calendar.current.isDateInToday(day) {
            TimelineView(.everyMinute) { ctx in
                let start = Calendar.current.startOfDay(for: ctx.date)
                let y = ctx.date.timeIntervalSince(start) / 3600 * hourHeight
                HStack(spacing: 0) {
                    Circle().fill(Palette.accent).frame(width: 10, height: 10)
                    Rectangle().fill(Palette.accent).frame(height: 2)
                }
                .padding(.leading, rulerWidth + 4)
                .offset(y: y - 5)
                .allowsHitTesting(false)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        guard hour > 0 else { return "" }
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return date.formatted(.dateTime.hour())
    }
}
