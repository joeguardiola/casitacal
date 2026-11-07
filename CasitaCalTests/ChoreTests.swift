import Testing
import Foundation
@testable import CasitaCal

struct ChoreLogicTests {
    let kid = UUID(), mom = UUID()

    func chore(_ title: String, _ kind: ChoreRule.Kind, start: String = "2026-11-02", who: [UUID] = [], stars: Int = 1) -> Chore {
        Chore(id: UUID(), title: title, emoji: "⭐️", assignees: who, rule: ChoreRule(kind: kind, startDay: start),
              timeOfDay: .anytime, stars: stars, sortOrder: 0)
    }

    @Test func dailyStartsOnStartDay() {
        let r = ChoreRule(kind: .daily, startDay: "2026-11-05")
        #expect(!r.isScheduled(on: "2026-11-04"))
        #expect(r.isScheduled(on: "2026-11-05"))
        #expect(r.isScheduled(on: "2026-12-25"))
    }

    @Test func weekdayMasks() {
        let weekdays = ChoreRule(kind: .days(mask: ChoreRule.weekdaysMask), startDay: "2026-11-01")
        #expect(weekdays.isScheduled(on: "2026-11-09"))   // Monday
        #expect(!weekdays.isScheduled(on: "2026-11-08"))  // Sunday
        let weekends = ChoreRule(kind: .days(mask: ChoreRule.weekendsMask), startDay: "2026-11-01")
        #expect(weekends.isScheduled(on: "2026-11-07"))   // Saturday
        #expect(!weekends.isScheduled(on: "2026-11-06"))  // Friday
    }

    @Test func columnsSplitByPersonAndAnyone() {
        let bed = chore("Bed", .daily, who: [kid])
        let dog = chore("Dog", .daily)
        let both = chore("Dishes", .daily, who: [kid, mom])
        let all = [bed, dog, both]
        #expect(ChoreLogic.chores(all, completions: [], member: kid, day: "2026-11-09", today: "2026-11-09").map(\.title).sorted() == ["Bed", "Dishes"])
        #expect(ChoreLogic.chores(all, completions: [], member: mom, day: "2026-11-09", today: "2026-11-09").map(\.title) == ["Dishes"])
        #expect(ChoreLogic.chores(all, completions: [], member: nil, day: "2026-11-09", today: "2026-11-09").map(\.title) == ["Dog"])
    }

    @Test func missedOneOffCarriesToTodayUntilDone() {
        let c = chore("Return library books", .once, start: "2026-11-05", who: [kid])
        #expect(ChoreLogic.chores([c], completions: [], member: kid, day: "2026-11-09", today: "2026-11-09").count == 1)
        #expect(ChoreLogic.chores([c], completions: [], member: kid, day: "2026-11-10", today: "2026-11-09").isEmpty)
        let doneToday = [ChoreCompletion(choreID: c.id, day: "2026-11-09", memberID: kid)]
        #expect(ChoreLogic.chores([c], completions: doneToday, member: kid, day: "2026-11-09", today: "2026-11-09").count == 1)
        let doneEarlier = [ChoreCompletion(choreID: c.id, day: "2026-11-06", memberID: kid)]
        #expect(ChoreLogic.chores([c], completions: doneEarlier, member: kid, day: "2026-11-09", today: "2026-11-09").isEmpty)
    }

    @Test func starsCountOnlyThatPersonsCompletionsInRange() {
        let a = chore("A", .daily, who: [kid, mom], stars: 2)
        let b = chore("B", .daily, who: [kid], stars: 3)
        let done = [
            ChoreCompletion(choreID: a.id, day: "2026-11-09", memberID: kid),
            ChoreCompletion(choreID: b.id, day: "2026-11-10", memberID: kid),
            ChoreCompletion(choreID: a.id, day: "2026-11-09", memberID: mom),
            ChoreCompletion(choreID: b.id, day: "2026-11-20", memberID: kid), // next week
        ]
        #expect(ChoreLogic.stars(for: kid, days: ["2026-11-09", "2026-11-10"], chores: [a, b], completions: done) == 5)
    }
}

@MainActor
struct ChoreStoreTests {
    @Test func saveToggleAndDeleteRoundTrip() {
        let p = Persistence(inMemory: true)
        let store = ChoreStore(persistence: p)
        let kid = UUID()
        let today = Date()
        let c = Chore(id: UUID(), title: "Feed dog", emoji: "🐶", assignees: [kid],
                      rule: ChoreRule(kind: .daily, startDay: DayKey.from(today)), timeOfDay: .morning, stars: 2, sortOrder: 0)
        store.save(c)
        #expect(store.chores(for: kid, on: today).map(\.title) == ["Feed dog"])
        store.toggle(c, member: kid, on: today)
        #expect(store.isDone(c, member: kid, on: today))
        #expect(store.weeklyStars(for: kid, weekOf: today) == 2)
        store.toggle(c, member: kid, on: today)
        #expect(!store.isDone(c, member: kid, on: today))
        store.delete(c)
        #expect(store.chores.isEmpty)
    }

    @Test func seedsDefaultListsOnce() {
        let p = Persistence(inMemory: true)
        p.seedListsIfNeeded()
        p.seedListsIfNeeded()
        let count = (try? p.context.count(for: .init(entityName: "CDList"))) ?? 0
        #expect(count == 2)
    }
}
