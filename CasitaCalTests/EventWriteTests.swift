import Testing
import Foundation
@testable import CasitaCal

struct EventWriteTests {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.firstWeekday = 2
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    let joe = Member(name: "Joe", emoji: "🧔", color: .peacock)
    let kid = Member(name: "Kid", emoji: "🧒", color: .sage)

    @Test func allDayBodyUsesExclusiveEndDate() {
        var d = EventDraft(day: date(2026, 11, 9), calendar: cal)
        d.title = "Trip"
        d.isAllDay = true
        d.start = date(2026, 11, 9)
        d.end = date(2026, 11, 11) // editor shows last day inclusive
        let body = d.body(members: [], includeRecurrence: true, calendar: cal)
        #expect(body.start == GCalEventTime(date: "2026-11-09"))
        #expect(body.end == GCalEventTime(date: "2026-11-12"))
        #expect(body.recurrence == nil)
        #expect(body.colorId == nil)
    }

    @Test func timedBodyHasOffsetZoneRepeatAndPeople() {
        var d = EventDraft(day: date(2026, 11, 9), calendar: cal)
        d.title = "  Swim  "
        d.start = date(2026, 11, 9, 16)
        d.end = date(2026, 11, 9, 17)
        d.repeatRule = .weekly
        d.people = [kid.id, joe.id]
        let body = d.body(members: [joe, kid], includeRecurrence: true, calendar: cal)
        #expect(body.summary == "Swim")
        #expect(body.start.dateTime == "2026-11-09T16:00:00-08:00")
        #expect(body.start.timeZone == "America/Los_Angeles")
        #expect(body.recurrence == ["RRULE:FREQ=WEEKLY"])
        #expect(body.colorId == kid.color.googleColorId)
        #expect(body.membersTag == "\(kid.id.uuidString),\(joe.id.uuidString)")
    }

    @Test func timedBodyNullsDateSoPatchCanSwitchFromAllDay() throws {
        var d = EventDraft(day: date(2026, 11, 9), calendar: cal)
        d.title = "x"
        let json = String(data: try JSONEncoder().encode(d.body(members: [], includeRecurrence: false, calendar: cal)), encoding: .utf8)!
        #expect(json.contains("\"date\":null"))
        #expect(!json.contains("recurrence"))
    }

    @Test func seriesEditKeepsFirstDayButTakesNewTime() {
        var d = EventDraft(day: date(2026, 11, 18), calendar: cal)
        d.start = date(2026, 11, 18, 17, 30) // edited instance moved to 5:30
        d.end = date(2026, 11, 18, 18, 30)
        let r = EventStore.retime(d, ontoSeriesStarting: date(2026, 9, 2, 16), calendar: cal)
        #expect(r.start == date(2026, 9, 2, 17, 30))
        #expect(r.end == date(2026, 9, 2, 18, 30))
    }

    @Test func cacheMergeReplacesOnlyTheFetchedRange() {
        func e(_ id: String, _ s: Date, _ en: Date) -> CalendarEvent {
            CalendarEvent(id: id, title: id, start: s, end: en, isAllDay: false, taggedMemberIDs: [])
        }
        let lastWeek = e("old", date(2026, 11, 2, 9), date(2026, 11, 2, 10))
        let deleted = e("gone", date(2026, 11, 10, 9), date(2026, 11, 10, 10))
        let fresh = e("new", date(2026, 11, 11, 9), date(2026, 11, 11, 10))
        let week = DateInterval(start: date(2026, 11, 9), end: date(2026, 11, 16))
        let merged = EventCache.merge([fresh], into: [lastWeek, deleted], covering: week)
        #expect(merged.map(\.id) == ["old", "new"])
    }

    @Test func weekStartsMonday() {
        let range = CalendarRanges.range(for: .week, anchor: date(2026, 11, 8), calendar: cal) // a Sunday
        let days = CalendarRanges.days(in: range, calendar: cal)
        #expect(days.first == date(2026, 11, 2)) // Monday
        #expect(days.last == date(2026, 11, 8))  // that Sunday ends the week
        let grid = CalendarRanges.monthGrid(for: date(2026, 11, 15), calendar: cal)
        #expect(cal.component(.weekday, from: grid.first!) == 2)
    }

    @Test func repeatRules() {
        #expect(RepeatRule.never.rrule == nil)
        #expect(RepeatRule.weekdays.rrule == "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR")
        #expect(RepeatRule.biweekly.rrule == "RRULE:FREQ=WEEKLY;INTERVAL=2")
    }
}

struct KioskTests {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: h, minute: m))! }
    let night = (DateComponents(hour: 22, minute: 0), DateComponents(hour: 6, minute: 30))

    func mode(idle: TimeInterval, at date: Date, slideshow: Int = 10, sleep: Bool = true,
              current: KioskController.Mode = .active, dark: Bool = false) -> KioskController.Mode {
        KioskController.mode(idle: idle, now: date, slideshowAfterMinutes: slideshow, sleepEnabled: sleep,
                             sleepStart: night.0, sleepEnd: night.1, current: current, roomIsDark: dark, calendar: cal)
    }

    @Test func darkRoomShowsClockInsteadOfSlideshowDuringDay() {
        #expect(mode(idle: 5, at: at(14), dark: true) == .active)   // just touched
        #expect(mode(idle: 10, at: at(14), dark: true) == .sleep)   // lights off: clock within ~10 s
        #expect(mode(idle: 3 * 60, at: at(14), dark: true) == .sleep)
        #expect(mode(idle: 20 * 60, at: at(14), current: .slideshow, dark: true) == .sleep)
        // Lights back on: slideshow again
        #expect(mode(idle: 20 * 60, at: at(14), current: .sleep, dark: false) == .slideshow)
    }

    @Test func nightHoursWithLightsOnWaitLonger() {
        #expect(mode(idle: 30, at: at(23), dark: false) == .active)
        #expect(mode(idle: 30, at: at(23), dark: true) == .sleep)
    }

    @Test func itsDarkNowSetsTheCutOffJustAboveTheReading() {
        // The kitchen's darkest Auto-Brightness level was 0.25 with the lights on at 0.50.
        let cutOff = KioskController.threshold(forDarkReading: 0.25)
        #expect(abs(cutOff - 0.29) < 0.001)
        #expect(KioskController.isDark(brightness: 0.25, threshold: cutOff, wasDark: false))
        #expect(!KioskController.isDark(brightness: 0.50, threshold: cutOff, wasDark: true))
    }

    @Test func darknessHasHysteresis() {
        #expect(KioskController.isDark(brightness: 0.10, threshold: 0.15, wasDark: false))
        #expect(!KioskController.isDark(brightness: 0.18, threshold: 0.15, wasDark: false))
        #expect(KioskController.isDark(brightness: 0.18, threshold: 0.15, wasDark: true))   // stays dark
        #expect(!KioskController.isDark(brightness: 0.25, threshold: 0.15, wasDark: true))  // clearly light
    }

    @Test func overnightWindowCrossesMidnight() {
        #expect(KioskController.isWithin(at(23), start: night.0, end: night.1, calendar: cal))
        #expect(KioskController.isWithin(at(3), start: night.0, end: night.1, calendar: cal))
        #expect(!KioskController.isWithin(at(6, 30), start: night.0, end: night.1, calendar: cal))
        #expect(!KioskController.isWithin(at(12), start: night.0, end: night.1, calendar: cal))
    }

    @Test func daytimeIdleStartsSlideshow() {
        #expect(mode(idle: 60, at: at(14)) == .active)
        #expect(mode(idle: 10 * 60, at: at(14)) == .slideshow)
        #expect(mode(idle: 3600, at: at(14), slideshow: 0) == .active) // slideshow off
    }

    @Test func nightSleepsAfterShortIdleEvenFromSlideshow() {
        #expect(mode(idle: 30, at: at(23)) == .active)          // just touched: stay awake
        #expect(mode(idle: 3 * 60, at: at(23)) == .sleep)
        #expect(mode(idle: 3 * 60, at: at(23), current: .slideshow) == .sleep)
        #expect(mode(idle: 3 * 60, at: at(23), sleep: false) == .active)
    }

    @Test func manualSlideshowPersistsUntilTouched() {
        #expect(mode(idle: 5, at: at(14), current: .slideshow) == .slideshow)
    }
}

struct SlideshowFitTests {
    let landscape = CGSize(width: 1180, height: 820)

    @Test func portraitPhotosStayWholeOnALandscapeScreen() {
        #expect(!SlideshowFit.fillsScreen(photo: CGSize(width: 3024, height: 4032), screen: landscape))
    }

    @Test func wideScreenshotsStayWhole() {
        #expect(!SlideshowFit.fillsScreen(photo: CGSize(width: 1920, height: 1080), screen: landscape))
    }

    @Test func normalLandscapePhotosFill() {
        #expect(SlideshowFit.fillsScreen(photo: CGSize(width: 4032, height: 3024), screen: landscape))
        #expect(SlideshowFit.fillsScreen(photo: CGSize(width: 6000, height: 4000), screen: landscape))
    }

    @Test func rotatingTheIPadSwapsTheAnswer() {
        let portrait = CGSize(width: 820, height: 1180)
        #expect(SlideshowFit.fillsScreen(photo: CGSize(width: 3024, height: 4032), screen: portrait))
    }
}

struct ManualSlideshowTests {
    func mode(idle: TimeInterval, hour: Int, current: KioskController.Mode = .slideshow,
              dark: Bool = false, manual: Bool = true) -> KioskController.Mode {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
        return KioskController.mode(
            idle: idle, now: date, slideshowAfterMinutes: 10, sleepEnabled: true,
            sleepStart: DateComponents(hour: 22, minute: 0), sleepEnd: DateComponents(hour: 6, minute: 30),
            current: current, roomIsDark: dark, manualSlideshow: manual
        )
    }

    @Test func survivesNightAndDarkRoomRules() {
        #expect(mode(idle: 15, hour: 23) == .slideshow)
        #expect(mode(idle: 5 * 60, hour: 14, dark: true) == .slideshow)
    }

    @Test func givesWayToTheNightClockEventually() {
        #expect(mode(idle: 31 * 60, hour: 23) == .sleep)
    }

    @Test func runsAsLongAsYouLikeInTheDaytime() {
        #expect(mode(idle: 5 * 3600, hour: 14) == .slideshow)
    }

    @Test func automaticSlideshowStillStopsAtNight() {
        #expect(mode(idle: 15, hour: 23, manual: false) == .active)
    }
}

struct QuickAddDayTests {
    let now = Date()
    var thursday: Date { Calendar.app.date(byAdding: .day, value: 2, to: Calendar.app.startOfDay(for: now))! }
    var thursdayText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM d, yyyy"
        return f.string(from: thursday)
    }

    @Test func todayIsLeftAlone() {
        #expect(EventStore.quickAddText("Soccer 4pm", day: now, now: now) == "Soccer 4pm")
    }

    @Test func noDayGetsTheChosenDay() {
        #expect(EventStore.quickAddText("Soccer 4pm", day: thursday, now: now) == "Soccer 4pm on \(thursdayText)")
        #expect(EventStore.quickAddText("Lunch with Sam", day: thursday, now: now) == "Lunch with Sam on \(thursdayText)")
    }

    @Test func aNamedDayWins() {
        let nextWeek = Calendar.app.date(byAdding: .day, value: 8, to: now)!
        let text = "Dentist \(nextWeek.formatted(.dateTime.month(.wide).day())) 3pm"
        #expect(EventStore.quickAddText(text, day: thursday, now: now) == text)
        #expect(EventStore.quickAddText("Party tomorrow at 6", day: thursday, now: now) == "Party tomorrow at 6")
        #expect(EventStore.quickAddText("Pizza tonight", day: thursday, now: now) == "Pizza tonight")
    }
}
