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

    @Test func allDayEndIsExclusive() {
        // Google: a single all-day event on the 9th has end.date = the 10th.
        let e = event("trip", date(2026, 11, 9), date(2026, 11, 10), allDay: true)
        #expect(DayLayout.allDay([e], on: date(2026, 11, 9), calendar: cal).count == 1)
        #expect(DayLayout.allDay([e], on: date(2026, 11, 10), calendar: cal).isEmpty)
    }

    @Test func rollingWeekStartsOnAnchorAcrossMonthEnd() {
        let days = CalendarRanges.rollingDays(from: date(2026, 11, 29, 15), count: 5, calendar: cal)
        #expect(days == [date(2026, 11, 29), date(2026, 11, 30), date(2026, 12, 1), date(2026, 12, 2), date(2026, 12, 3)])
    }

    @Test func rollingWeekCrossesDaylightSavingEnd() {
        // US DST ends Nov 1 2026; every column is still a distinct local midnight.
        let days = CalendarRanges.rollingDays(from: date(2026, 10, 30), count: 5, calendar: cal)
        #expect(days == [date(2026, 10, 30), date(2026, 10, 31), date(2026, 11, 1), date(2026, 11, 2), date(2026, 11, 3)])
    }

    @Test func pagingMovesByWholeWindows() {
        let start = date(2026, 11, 8)
        #expect(CalendarRanges.stepRolling(start, count: 5, by: 1, calendar: cal) == date(2026, 11, 13))
        #expect(CalendarRanges.stepRolling(start, count: 7, by: -1, calendar: cal) == date(2026, 11, 1))
    }

    @Test func anchorFollowsTodayAtMidnightOnlyIfOnToday() {
        let yesterday = date(2026, 11, 8, 12), now = date(2026, 11, 9, 0, 1)
        #expect(CalendarRanges.rolledAnchor(date(2026, 11, 8, 7), previousToday: yesterday, now: now, calendar: cal) == now)
        let pagedAway = date(2026, 11, 20)
        #expect(CalendarRanges.rolledAnchor(pagedAway, previousToday: yesterday, now: now, calendar: cal) == pagedAway)
    }

    @Test func columnWidthsFillTheSpace() {
        #expect(WeekColumns.widths(total: 540, spacing: 10, count: 5, widened: nil) == [100, 100, 100, 100, 100])
        let w = WeekColumns.widths(total: 540, spacing: 10, count: 5, widened: 0)
        #expect(abs(w[0] - 2 * w[1]) < 0.001)
        #expect(abs(w.reduce(0, +) + 40 - 540) < 0.001)
        #expect(WeekColumns.widths(total: 540, spacing: 10, count: 5, widened: 9) == [100, 100, 100, 100, 100])
    }

    @Test func compactTimesAreShort() {
        let us = Locale(identifier: "en_US")
        let t = { (s: Date, e: Date) in self.event("x", s, e).compactTimeText(calendar: self.cal, locale: us) }
        #expect(t(date(2026, 11, 9, 16), date(2026, 11, 9, 17)) == "4–5p")
        #expect(t(date(2026, 11, 9, 9, 30), date(2026, 11, 9, 10)) == "9:30–10a")
        #expect(t(date(2026, 11, 9, 11), date(2026, 11, 9, 13)) == "11a–1p")
        #expect(t(date(2026, 11, 9, 0), date(2026, 11, 9, 12)) == "12a–12p")
        #expect(t(date(2026, 11, 9, 16), date(2026, 11, 9, 16)) == "4p")
        let allDay = event("x", date(2026, 11, 9), date(2026, 11, 10), allDay: true)
        #expect(allDay.compactTimeText(calendar: cal, locale: us) == "All day")
    }

    @Test func monthRowsShareHeightAndLimitChips() {
        #expect(MonthCells.rowHeight(total: 540, rows: 6, spacing: 6) == 85)
        #expect(MonthCells.chipCount(rowHeight: 90) == 2)
        #expect(MonthCells.chipCount(rowHeight: 10) == 0)
        #expect(MonthCells.chipCount(rowHeight: 900) == MonthCells.maxChips)
    }

    @Test func compactStartIsJustTheStart() {
        let us = Locale(identifier: "en_US")
        let e = event("x", date(2026, 11, 9, 9, 30), date(2026, 11, 9, 11))
        #expect(e.compactStartText(calendar: cal, locale: us) == "9:30a")
    }

    @Test func compactTimesKeep24HourClocks() {
        let e = event("x", date(2026, 11, 9, 16), date(2026, 11, 9, 17, 30))
        #expect(e.compactTimeText(calendar: cal, locale: Locale(identifier: "en_GB@hours=h23")) == "16:00–17:30")
    }

    @Test func swipeNeedsAClearHorizontalMove() {
        #expect(SwipePaging.direction(translation: CGSize(width: -90, height: 5), velocity: .zero) == .next)
        #expect(SwipePaging.direction(translation: CGSize(width: 90, height: 5), velocity: .zero) == .previous)
        #expect(SwipePaging.direction(translation: CGSize(width: -35, height: 0), velocity: CGSize(width: -700, height: 0)) == .next)
        #expect(SwipePaging.direction(translation: CGSize(width: -20, height: 0), velocity: .zero) == nil)
        #expect(SwipePaging.direction(translation: CGSize(width: 90, height: 120), velocity: .zero) == nil)
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

    @Test func nameInTitleMatchesWholeWords() {
        let e = { (t: String) in CalendarEvent(id: "e", title: t, start: .now, end: .now, isAllDay: false, taggedMemberIDs: []) }
        #expect(EventMapper.members(for: e("Joe dentist"), from: [joe, kid]) == [joe])
        #expect(EventMapper.members(for: e("Dentist – JOE's checkup"), from: [joe, kid]) == [joe])
        #expect(EventMapper.members(for: e("Joey's party"), from: [joe, kid]).isEmpty)
        #expect(EventMapper.members(for: e("Joe + Kid swim"), from: [joe, kid]) == [joe, kid])
    }

    @Test func nicknamesAndAccentsMatch() {
        var dad = joe
        dad.nicknames = ["Dad", "Papá"]
        let e = { (t: String) in CalendarEvent(id: "e", title: t, start: .now, end: .now, isAllDay: false, taggedMemberIDs: []) }
        #expect(EventMapper.members(for: e("Pick up dad"), from: [dad]) == [dad])
        #expect(EventMapper.members(for: e("Papa's golf"), from: [dad]) == [dad])
        #expect(EventMapper.members(for: e("Daddy daycare"), from: [dad]).isEmpty)
    }

    @Test func colorBeatsTitleAndSourceIsReported() {
        let e = CalendarEvent(id: "e", title: "Kid soccer", start: .now, end: .now, isAllDay: false, colorId: "7", taggedMemberIDs: [])
        let a = EventMapper.assignment(for: e, from: [joe, kid])
        #expect(a.members == [joe])
        #expect(a.source == .color)
    }

    @Test func patchEncodesNullColorToClear() throws {
        let json = String(data: try JSONEncoder().encode(GCalEventPatch(colorId: nil, sharedProperties: ["k": ""])), encoding: .utf8)!
        #expect(json.contains("\"colorId\":null"))
        #expect(json.contains("\"shared\":{\"k\":\"\"}"))
    }

    @Test func oldSavedMembersStillDecode() throws {
        let old = #"[{"id":"\#(UUID().uuidString)","name":"Joe","emoji":"🧔","color":"7","role":"adult"}]"#
        let decoded = try JSONDecoder().decode([Member].self, from: Data(old.utf8))
        #expect(decoded.first?.nicknames == [])
    }

    @Test func visibilityFollowsFilter() {
        let e = event(colorId: "7")
        #expect(EventMapper.isVisible(e, members: [joe, kid], hidden: []))
        #expect(!EventMapper.isVisible(e, members: [joe, kid], hidden: [joe.id]))
        #expect(EventMapper.isVisible(event(), members: [joe, kid], hidden: [joe.id, kid.id]))
    }
}

struct WeekColumnChoiceTests {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    func date(_ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))!
    }

    var days: [Date] { (10...14).map { date($0) } }

    @Test func todayIsWideByDefault() {
        #expect(WeekColumns.widenedIndex(.automatic, days: days, today: date(10, 15), calendar: cal) == 0)
        #expect(WeekColumns.widenedIndex(.automatic, days: days, today: date(12, 8), calendar: cal) == 2)
    }

    @Test func noWideColumnWhenTodayIsOffScreen() {
        #expect(WeekColumns.widenedIndex(.automatic, days: days, today: date(20), calendar: cal) == nil)
    }

    @Test func chosenDayAndEqualAreKept() {
        #expect(WeekColumns.widenedIndex(.day(date(13)), days: days, today: date(10), calendar: cal) == 3)
        #expect(WeekColumns.widenedIndex(.equal, days: days, today: date(10), calendar: cal) == nil)
    }

    @Test func tappingTheWideColumnEvensThemOut() {
        let today = Date()
        let week = (0..<5).compactMap { Calendar.app.date(byAdding: .day, value: $0, to: Calendar.app.startOfDay(for: today)) }
        #expect(WeekColumns.toggled(.automatic, tapped: 0, days: week, today: today) == .equal)
        #expect(WeekColumns.toggled(.automatic, tapped: 2, days: week, today: today) == .day(week[2]))
        #expect(WeekColumns.toggled(.equal, tapped: 0, days: week, today: today) == .day(week[0]))
    }

    @Test func feastsGoToTheBottomOfTheDay() {
        let day = Calendar.app.startOfDay(for: Date())
        let next = Calendar.app.date(byAdding: .day, value: 1, to: day)!
        let feast = CalendarEvent(id: "feast", title: "Saint Martin", start: day, end: next, isAllDay: true,
                                  taggedMemberIDs: [], feastOverlayDay: DayKey.from(day))
        let allDay = CalendarEvent(id: "trip", title: "Trip", start: day, end: next, isAllDay: true, taggedMemberIDs: [])
        let late = CalendarEvent(id: "late", title: "Late", start: day.addingTimeInterval(22 * 3600),
                                 end: day.addingTimeInterval(23 * 3600), isAllDay: false, taggedMemberIDs: [])
        #expect(DayLayout.agenda([feast, late, allDay], on: day).map(\.id) == ["trip", "late", "feast"])
    }
}
