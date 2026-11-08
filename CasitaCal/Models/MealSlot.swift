import Foundation

/// Meal times on the plan (stored as the raw value).
enum MealSlot: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var emoji: String {
        switch self {
        case .breakfast: "🥞"
        case .lunch: "🥪"
        case .dinner: "🍝"
        case .snack: "🍎"
        }
    }
}
