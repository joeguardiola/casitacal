import Testing
import Foundation
@testable import CasitaCal

struct EventLayoutTests {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.firstWeekday = 1
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, title: id, start: start, end: end, isAllDay: allDay, taggedMemberIDs: [])
    }

    @Test func nonOverlappingEventsGetOneColumn() {
        let day = date(2026, 11, 9)
        let a = event("a", date(2026, 11, 9, 9), date(2026, 11, 9, 10))
        let b = event("b", date(2026, 11, 9, 10), date(2026, 11, 9, 11))
        let laid = DayLayout.timed([a, b], on: day, calendar: cal)
        #expect(laid.map(\.columnCount) == [1, 1])
        #expect(laid.map(\.column) == [0, 0])
    }

    @Test func overlappingEventsSplitColumns() {
        let day = date(2026, 11, 9)
        let a = event("a", date(2026, 11, 9, 9), date(2026, 11, 9, 11))
        let b = event("b", date(2026, 11, 9, 10), date(2026, 11, 9, 12))
        let c = event("c", date(2026, 11, 9, 11), date(2026, 11, 9, 12)) // reuses a's column
        let laid = DayLayout.timed([a, b, c], on: day, calendar: cal)
        let byId = Dictionary(uniqueKeysWithValues: laid.map { ($0.id, $0) })
        #expect(byId["a"]!.column == 0)
        #expect(byId["b"]!.column == 1)
        #expect(byId["c"]!.column == 0)
        #expect(laid.allSatisfy { $0.columnCount == 2 })
    }

    @Test func overnightEventIsClippedToEachDay() {
        let e = event("late", date(2026, 11, 9, 22), date(2026, 11, 10, 2))
        let mon = DayLayout.timed([e], on: date(2026, 11, 9), calendar: cal)
        let tue = DayLayout.timed([e], on: date(2026, 11, 10), calendar: cal)
        #expect(mon.first?.end == date(2026, 11, 10))
        #expect(tue.first?.start == date(2026, 11, 10))
        #expect(tue.first?.end == date(2026, 11, 10, 2))
    }

    @Test func allDayEndIsExclusive() {
        // Google: a single all-day event on the 9th has end.date = the 10th.
        let e = event("trip", date(2026, 11, 9), date(2026, 11, 10), allDay: true)
        #expect(DayLayout.allDay([e], on: date(2026, 11, 9), calendar: cal).count == 1)
        #expect(DayLayout.allDay([e], on: date(2026, 11, 10), calendar: cal).isEmpty)
    }

    @Test func monthGridCoversWholeWeeks() {
        let grid = CalendarRanges.monthGrid(for: date(2026, 11, 15), calendar: cal)
        #expect(grid.count % 7 == 0)
        #expect(grid.first == date(2026, 11, 1)) // Nov 1 2026 is a Sunday
        #expect(grid.contains(date(2026, 11, 30)))
    }

    @Test func dstWeekStillHasSevenDays() {
        // US DST ends Nov 1 2026.
        let range = CalendarRanges.range(for: .week, anchor: date(2026, 11, 3), calendar: cal)
        #expect(CalendarRanges.days(in: range, calendar: cal).count == 7)
    }
}

struct EventParsingTests {
    @Test func parsesTimedEvent() {
        let g = GCalEvent(
            id: "1", summary: "Soccer",
            start: GCalEventTime(dateTime: "2026-11-09T16:00:00-08:00"),
            end: GCalEventTime(dateTime: "2026-11-09T17:30:00-08:00")
        )
        let e = CalendarEvent(google: g)!
        #expect(!e.isAllDay)
        #expect(e.end.timeIntervalSince(e.start) == 90 * 60)
        #expect(e.title == "Soccer")
    }

    @Test func parsesAllDayEventAndMemberTags() {
        let id1 = UUID(), id2 = UUID()
        let g = GCalEvent(
            id: "2", summary: nil, colorId: "7",
            start: GCalEventTime(date: "2026-11-09"),
            end: GCalEventTime(date: "2026-11-11"),
            extendedProperties: .init(shared: [CalendarEvent.membersPropertyKey: "\(id1),\(id2)"])
        )
        let e = CalendarEvent(google: g)!
        #expect(e.isAllDay)
        #expect(e.title == "(No title)")
        #expect(e.taggedMemberIDs == [id1, id2])
        #expect(e.colorId == "7")
    }

    @Test func rejectsEventWithoutTimes() {
        #expect(CalendarEvent(google: GCalEvent(id: "x")) == nil)
    }
}

struct EventMapperTests {
    let joe = Member(name: "Joe", emoji: "🧔", color: .peacock)
    let kid = Member(name: "Kid", emoji: "🧒", color: .sage)

    func event(colorId: String? = nil, tags: [UUID] = []) -> CalendarEvent {
        CalendarEvent(id: "e", title: "t", start: .now, end: .now, isAllDay: false, colorId: colorId, taggedMemberIDs: tags)
    }

    @Test func colorIdMapsToOwner() {
        #expect(EventMapper.members(for: event(colorId: "7"), from: [joe, kid]) == [joe])
    }

    @Test func tagsBeatColor() {
        let e = event(colorId: "7", tags: [kid.id, joe.id])
        #expect(EventMapper.members(for: e, from: [joe, kid]) == [kid, joe])
    }

    @Test func unknownColorMeansEveryone() {
        #expect(EventMapper.members(for: event(colorId: "11"), from: [joe, kid]).isEmpty)
        #expect(EventMapper.members(for: event(), from: [joe, kid]).isEmpty)
    }

    @Test func visibilityFollowsFilter() {
        let e = event(colorId: "7")
        #expect(EventMapper.isVisible(e, members: [joe, kid], hidden: []))
        #expect(!EventMapper.isVisible(e, members: [joe, kid], hidden: [joe.id]))
        #expect(EventMapper.isVisible(event(), members: [joe, kid], hidden: [joe.id, kid.id]))
    }
}
