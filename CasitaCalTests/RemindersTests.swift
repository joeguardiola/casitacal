import Testing
@testable import CasitaCal

struct RemindersListTests {
    private func list(_ id: String, _ title: String) -> ReminderList {
        ReminderList(id: id, title: title, colorHex: 0)
    }

    @Test func defaultsToShoppingListsWhenPresent() {
        let lists = [list("a", "Work"), list("b", "Shopping List"), list("c", "Groceries"), list("d", "Reminders")]
        #expect(RemindersStore.defaultShown(lists) == ["b", "c"])
    }

    @Test func defaultsToEverythingOtherwise() {
        let lists = [list("a", "Work"), list("b", "Family")]
        #expect(RemindersStore.defaultShown(lists) == ["a", "b"])
    }

    @Test func guessesEmojiFromTitle() {
        #expect(ReminderList.emoji(for: "Shopping List") == "🛒")
        #expect(ReminderList.emoji(for: "Packing for Maui") == "🧳")
        #expect(ReminderList.emoji(for: "Random") == "📝")
    }
}
