import Testing
@testable import CasitaCal

struct ShoppingItemsTests {
    @Test func cleansIngredientLines() {
        #expect(ShoppingItems.item(from: "1 ½ pounds ground beef, trimmed").listTitle == "Ground beef (1 ½ pounds)")
        #expect(ShoppingItems.item(from: "8 ounces unsalted butter (2 sticks; 225g)").listTitle == "Unsalted butter (8 ounces)")
        #expect(ShoppingItems.item(from: "2 tsp smoked paprika ($0.20)").listTitle == "Smoked paprika (2 tsp)")
        #expect(ShoppingItems.item(from: "1 large onion, finely chopped").listTitle == "Large onion (1)")
        #expect(ShoppingItems.item(from: "Salt and pepper").listTitle == "Salt and pepper")
        #expect(ShoppingItems.item(from: "a pinch of salt").listTitle == "Salt (pinch)")
        #expect(ShoppingItems.item(from: "3 cloves garlic").listTitle == "Garlic (3 cloves)")
    }

    @Test func spotsItemsAlreadyOnTheList() {
        let existing = ["Milk", "Eggs", "Paper towels"]
        #expect(ShoppingItems.isAlreadyOnList(ShoppingItems.item(from: "2 cups whole milk"), existing: existing))
        #expect(ShoppingItems.isAlreadyOnList(ShoppingItems.item(from: "2 large eggs"), existing: existing))
        #expect(ShoppingItems.isAlreadyOnList(ShoppingItems.item(from: "1 egg"), existing: existing))
        #expect(!ShoppingItems.isAlreadyOnList(ShoppingItems.item(from: "1 cup flour"), existing: existing))
    }
}
