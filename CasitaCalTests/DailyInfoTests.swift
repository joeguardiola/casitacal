import CoreData
import Foundation
import Testing
@testable import CasitaCal

struct LiturgicalCalendarTests {
    static let entries: [FeastEntry] = {
        let url = Bundle.main.url(forResource: "feasts", withExtension: "json")
        return (try? JSONDecoder().decode([FeastEntry].self, from: Data(contentsOf: url ?? URL(fileURLWithPath: "/")))) ?? []
    }()

    func calendar(_ year: Int, ascensionOnSunday: Bool = true) -> LiturgicalCalendar {
        LiturgicalCalendar(year: year, entries: Self.entries, ascensionOnSunday: ascensionOnSunday)
    }

    func find(_ id: String, on day: String, ascensionOnSunday: Bool = true) -> Celebration? {
        calendar(Int(day.prefix(4)) ?? 0, ascensionOnSunday: ascensionOnSunday).celebrations(on: day).first { $0.entry.id == id }
    }

    @Test func feastDataLoads() {
        #expect(Self.entries.count > 90)
        #expect(Set(Self.entries.map(\.id)).count == Self.entries.count)
        #expect(Self.entries.allSatisfy { !$0.blurb.isEmpty })
    }

    @Test(arguments: [(2024, 3, 31), (2025, 4, 20), (2026, 4, 5), (2027, 3, 28), (2028, 4, 16), (2038, 4, 25), (2285, 3, 22)])
    func easterDates(year: Int, month: Int, day: Int) {
        let e = LiturgicalCalendar.easter(year: year)
        #expect(e.month == month && e.day == day)
    }

    @Test func moveableDaysFollowEaster() {
        #expect(find("ash-wednesday", on: "2026-02-18")?.isFastDay == true)
        #expect(find("good-friday", on: "2026-04-03")?.isFastDay == true)
        #expect(find("pentecost", on: "2026-05-24") != nil)
        #expect(find("corpus-christi", on: "2026-06-07") != nil)
        #expect(find("sacred-heart", on: "2026-06-12") != nil)
    }

    @Test func everyBookDayLandsOnTheCalendar() {
        for year in 2024...2040 {
            let cal = calendar(year)
            var day = DateComponents(calendar: Calendar(identifier: .gregorian), year: year, month: 1, day: 1).date ?? .distantPast
            var found: Set<String> = []
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
            day = utc.date(from: DateComponents(year: year, month: 1, day: 1)) ?? day
            while utc.component(.year, from: day) == year {
                let c = utc.dateComponents([.year, .month, .day], from: day)
                let key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
                found.formUnion(cal.celebrations(on: key).map(\.entry.id))
                day = utc.date(byAdding: .day, value: 1, to: day) ?? day
            }
            #expect(found == Set(Self.entries.map(\.id)), "\(year)")
        }
    }

    @Test func holyWeekAndOctaveDays() {
        #expect(find("lent-5", on: "2026-03-22") != nil)
        #expect(find("holy-monday", on: "2026-03-30") != nil)
        #expect(find("spy-wednesday", on: "2026-04-01") != nil)
        #expect(find("easter-saturday", on: "2026-04-11") != nil)
        #expect(find("immaculate-heart", on: "2026-06-13") != nil)
        #expect(find("christmas-eve", on: "2026-12-24") != nil)
    }

    @Test func indulgencesAndReadingsLoad() {
        let byID = Dictionary(uniqueKeysWithValues: Self.entries.map { ($0.id, $0) })
        #expect(byID["divine-mercy"]?.indulgence?.isEmpty == false)
        #expect(byID["christmas"]?.readings == ["Luke 2:1–20"])
        #expect(byID["patrick"]?.prayers?.contains("St. Patrick's Breastplate") == true)
    }

    @Test func ascensionFollowsTheSetting() {
        #expect(find("ascension", on: "2026-05-17")?.isObligation == false)
        #expect(find("ascension", on: "2026-05-14", ascensionOnSunday: false)?.isObligation == true)
        #expect(find("ascension", on: "2026-05-14") == nil)
    }

    @Test func obligationLiftedOnSaturdayAndMonday() {
        #expect(find("all-saints", on: "2025-11-01")?.isObligation == false)
        #expect(find("assumption", on: "2026-08-15")?.isObligation == false)
        #expect(find("mary-mother-god", on: "2024-01-01")?.isObligation == false)
        #expect(find("assumption", on: "2028-08-15")?.isObligation == true)
    }

    @Test func immaculateConceptionMovesOffSundayWithoutObligation() {
        #expect(find("immaculate", on: "2024-12-08") == nil)
        let moved = find("immaculate", on: "2024-12-09")
        #expect(moved?.isObligation == false)
        #expect(moved?.note != nil)
        #expect(find("immaculate", on: "2026-12-08")?.isObligation == true)
    }

    @Test func solemnitiesMoveOutOfTheWay() {
        #expect(find("joseph", on: "2023-03-20") != nil) // Mar 19 was a Lenten Sunday
        #expect(find("joseph", on: "2035-03-17") != nil) // Mar 19 fell in Holy Week
        #expect(find("annunciation", on: "2024-04-08") != nil) // Mar 25 fell in Holy Week
        #expect(find("john-baptist", on: "2022-06-23") != nil) // Sacred Heart on Jun 24
    }

    @Test func christmasCycleEdges() {
        #expect(find("baptism", on: "2024-01-08") != nil) // Epiphany on Jan 7, Baptism on Monday
        #expect(find("holy-family", on: "2022-12-30") != nil) // Christmas on a Sunday
        #expect(find("epiphany", on: "2026-01-04") != nil)
    }

    @Test func sundayOutranksASaintButTheDayStillShows() {
        let patrick = find("patrick", on: "2024-03-17")
        #expect(patrick?.isOutranked == true)
        #expect(patrick?.note != nil)
        #expect(find("patrick", on: "2026-03-17")?.isOutranked == false)
    }

    @Test func feastsOfTheLordReplaceSundays() {
        #expect(find("presentation", on: "2025-02-02")?.isOutranked == false)
    }
}

struct DailyContentTests {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }

    func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d)) ?? .distantPast
    }

    @Test func weekdayRules() {
        #expect(WeekdayRule(month: 2, weekday: 1, nth: 2).date(year: 2027, calendar: cal) == day(2027, 2, 14))
        #expect(WeekdayRule(month: 5, weekday: 2, nth: -1).date(year: 2026, calendar: cal) == day(2026, 5, 25))
        #expect(WeekdayRule(month: 12, weekday: 6, nth: -1).date(year: 2026, calendar: cal) == day(2026, 12, 25))
    }

    @Test func yearlyEvents() {
        let events = CurrentEvents.yearly(2026, calendar: cal)
        #expect(events.first { $0.title == "Thanksgiving" }?.day == day(2026, 11, 26))
        #expect(events.first { $0.title == "Grandparents Day" }?.day == day(2026, 9, 13))
        #expect(events.contains { $0.title == "Election Day" && $0.day == day(2026, 11, 3) })
        #expect(!CurrentEvents.yearly(2027, calendar: cal).contains { $0.title == "Election Day" })
    }

    @Test func upcomingStaysInsideTheWindow() {
        let events = [
            CurrentEvents.Event(day: day(2026, 11, 26), title: "Soon"),
            CurrentEvents.Event(day: day(2026, 12, 25), title: "Later"),
            CurrentEvents.Event(day: day(2026, 11, 1), title: "Past"),
        ]
        let found = CurrentEvents.upcoming(from: day(2026, 11, 22), horizon: 7, events: events, calendar: cal)
        #expect(found.map(\.event.title) == ["Soon"])
        #expect(found.first?.daysAway == 4)
    }

    @Test func nationalDaysMatchByDateOrRule() {
        #expect(NationalDay(on: "11-03", name: "Sandwich", idea: "").falls(on: day(2026, 11, 3), calendar: cal))
        let donut = NationalDay(rule: WeekdayRule(month: 6, weekday: 6, nth: 1), name: "Donut", idea: "")
        #expect(donut.falls(on: day(2026, 6, 5), calendar: cal))
        #expect(!donut.falls(on: day(2026, 6, 12), calendar: cal))
    }

    @Test func bundledListsDecode() throws {
        let days = try JSONDecoder().decode([NationalDay].self, from: Data(contentsOf: #require(Bundle.main.url(forResource: "national-days", withExtension: "json"))))
        let covered = Set(days.compactMap(\.on))
        #expect(covered.count == 366, "every date, leap day included")
        #expect(days.allSatisfy { $0.on != nil || $0.rule != nil })
        let thoughts = try JSONDecoder().decode([String].self, from: Data(contentsOf: #require(Bundle.main.url(forResource: "affirmations", withExtension: "json"))))
        #expect(thoughts.count >= 60)
    }

    @Test func grimHistoryIsLeftOut() {
        let facts = [
            HistoryFact(year: 1916, text: "Thousands were killed in the battle."),
            HistoryFact(year: 1895, text: "Wilhelm Röntgen discovered X-rays."),
            HistoryFact(year: 1950, text: "The warship was launched at Portsmouth."),
            HistoryFact(year: 1969, text: "The first episode of Sesame Street was broadcast."),
            HistoryFact(year: 2001, text: "A new tax law took effect."),
        ]
        #expect(WikipediaFeed.familyFriendly(facts).map(\.year) == [1895, 1969])
    }

    @Test func headerCardGetsTheMainClause() {
        let long = "The English rock group Led Zeppelin (pictured) released their fourth album, which became a best seller."
        #expect(WikipediaFeed.shortened(long) == "The English rock group Led Zeppelin released their fourth album")
        #expect(WikipediaFeed.shortened("William of Orange founded Leiden University, the oldest university in the Netherlands.") == "William of Orange founded Leiden University")
        // A comma before the main verb has to stay.
        let appositive = "Discovery, the third orbiter of the program, lifted off from Florida."
        #expect(WikipediaFeed.shortened(appositive) == "Discovery, the third orbiter of the program, lifted off from Florida")
    }

    @Test func headerCardPrefersTheShortestGoodFact() {
        let facts = [
            HistoryFact(year: 1900, text: "A very long and winding account of the first opera performed in a small town square."),
            HistoryFact(year: 1969, text: "Sesame Street first aired."),
            HistoryFact(year: 1916, text: "A battle."),
        ]
        #expect(WikipediaFeed.bestFact(facts)?.year == 1969)
    }

    @Test func wikipediaFeedParses() throws {
        let json = #"{"selected":[{"text":"Something happened.","year":1941,"pages":[{"normalizedtitle":"Thing","content_urls":{"desktop":{"page":"https://en.wikipedia.org/wiki/Thing"}}}]}]}"#
        let facts = try WikipediaFeed.parse(Data(json.utf8))
        #expect(facts.first?.year == 1941)
        #expect(facts.first?.pageURL == "https://en.wikipedia.org/wiki/Thing")
    }
}

struct FoodIdeaTests {
    @Test func dishNameDropsTheExplanation() {
        #expect(FoodIdea.dishName("Cullen skink, a Scottish smoked fish soup") == "Cullen skink")
        #expect(FoodIdea.dishName("Panettone") == "Panettone")
        #expect(FoodIdea.dishName("waffles — the Swedish way.") == "Waffles")
    }

    @Test func sortedIdeasGetTheRightButtons() {
        #expect(FoodIdea.canPlanDinner("Shepherd's pie"))
        #expect(FoodIdea.dishName("Three sisters stew of corn, beans and squash") == "Three sisters stew")
        #expect(FoodIdea.dishName("A fish fry") == "Fish fry")
        #expect(FoodIdea.hasRecipe("Cherry pie") && !FoodIdea.canPlanDinner("Cherry pie"))
        #expect(!FoodIdea.hasRecipe("Bring a meal to someone expecting"))
    }

    @Test func sortingFileMatchesTheFeastList() throws {
        struct Actions: Decodable { var skip: [String]; var recipeOnly: [String]; var names: [String: String] }
        func load(_ name: String) throws -> Data {
            try Data(contentsOf: try #require(Bundle.main.url(forResource: name, withExtension: "json")))
        }
        let actions = try JSONDecoder().decode(Actions.self, from: load("food-actions"))
        let feasts = try JSONDecoder().decode([FeastEntry].self, from: load("feasts"))
        let ideas = Set(feasts.flatMap { $0.food ?? [] })
        for idea in actions.skip + actions.recipeOnly + Array(actions.names.keys) {
            #expect(ideas.contains(idea), "\(idea) isn't in feasts.json")
        }
        for name in ideas.filter(FoodIdea.hasRecipe).map(FoodIdea.dishName) {
            #expect(name.count <= 36, "\(name) is too long for the meal plan")
        }
    }

    @Test func searchLinkSendsOnlyTheDish() throws {
        let url = try #require(FoodIdea.recipeSearchURL("Pastéis de nata, Portuguese custard tarts"))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        #expect(query == "Pastéis de nata recipe")
    }
}

@MainActor
struct PlanDinnerTests {
    let persistence = Persistence(inMemory: true)
    let day = "2026-11-08"

    @discardableResult
    func meal(_ title: String, slot: MealSlot = .dinner) -> CDMeal {
        let m = persistence.insert(CDMeal.self)
        m.id = UUID()
        m.title = title
        m.day = day
        m.slot = slot.rawValue
        m.household = persistence.household()
        return m
    }

    func dinners() -> [CDMeal] {
        let request = NSFetchRequest<CDMeal>(entityName: "CDMeal")
        request.predicate = NSPredicate(format: "day == %@ AND slot == %@", day, MealSlot.dinner.rawValue)
        return (try? persistence.context.fetch(request)) ?? []
    }

    @Test func fillsAnEmptyNight() {
        MealPlan.planDinner(title: "Soul bread", day: day, persistence: persistence)
        #expect(MealPlan.dinnerTitle(day: day, context: persistence.context) == "Soul bread")
    }

    @Test func replacesDuplicatesAndClearsTheOldRecipe() {
        let old = meal("Tacos")
        let recipe = persistence.insert(CDRecipe.self)
        recipe.id = UUID()
        recipe.title = "Tacos"
        old.recipe = recipe
        meal("Tacos again")
        MealPlan.planDinner(title: "Soul bread", day: day, persistence: persistence)
        #expect(dinners().count == 1)
        #expect(dinners().first?.title == "Soul bread")
        #expect(dinners().first?.recipe == nil)
    }

    @Test func leavesOtherMealsAlone() {
        let lunch = meal("Soup", slot: .lunch)
        MealPlan.planDinner(title: "Soul bread", day: day, persistence: persistence)
        #expect(lunch.title == "Soup")
    }
}

@MainActor
struct FeastOverlayTests {
    func store() -> DailyInfoStore {
        let defaults = UserDefaults(suiteName: "daily-tests-\(UUID().uuidString)") ?? .standard
        let s = DailyInfoStore(defaults: defaults)
        s.set(.catholic, on: true)
        s.showFeastsOnCalendar = true
        return s
    }

    var range: DateInterval {
        let c = Calendar.app
        let start = c.date(from: DateComponents(year: 2026, month: 3, day: 19)) ?? .distantPast
        return DateInterval(start: start, end: c.date(byAdding: .day, value: 1, to: start) ?? start)
    }

    @Test func offByDefault() {
        let defaults = UserDefaults(suiteName: "daily-tests-\(UUID().uuidString)") ?? .standard
        let s = DailyInfoStore(defaults: defaults)
        #expect(s.enabledTopics.isEmpty)
        #expect(s.feastOverlay(in: range, existing: []).isEmpty)
    }

    @Test func overlayNeverMatchesAFamilyMember() throws {
        let feast = try #require(store().feastOverlay(in: range, existing: []).first)
        #expect(feast.title == "Saint Joseph")
        #expect(feast.isFeastOverlay)
        let joseph = Member(name: "Joseph", emoji: "🧔", color: .graphite)
        #expect(EventMapper.members(for: feast, from: [joseph]).isEmpty)
    }

    @Test func aRealEventHidesTheOverlay() {
        let s = store()
        let real = CalendarEvent(
            id: "abc", title: "saint joseph", start: range.start, end: range.end, isAllDay: true,
            location: nil, notes: nil, colorId: nil, taggedMemberIDs: [], recurringEventId: nil, htmlLink: nil
        )
        #expect(s.feastOverlay(in: range, existing: [real]).isEmpty)
    }

    @Test func oldCachesStillDecode() throws {
        let json = #"[{"id":"x","title":"T","start":0,"end":0,"isAllDay":false,"taggedMemberIDs":[]}]"#
        let events = try JSONDecoder().decode([CalendarEvent].self, from: Data(json.utf8))
        #expect(events.first?.isFeastOverlay == false)
    }
}
