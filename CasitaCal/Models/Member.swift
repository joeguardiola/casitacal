import Foundation

/// A family member profile (Skylight-style). Each member owns one Google Calendar
/// event color so events tagged on a phone (by picking that color) map back to them.
struct Member: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var emoji: String
    var color: MemberColor
    var role: Role = .adult

    enum Role: String, Codable, CaseIterable, Sendable {
        case adult, kid
        var label: String { self == .adult ? "Adult" : "Kid" }
    }

    var initial: String { name.first.map { String($0).uppercased() } ?? "?" }
}

/// The 11 Google Calendar event colors. `rawValue` is Google's `colorId`.
enum MemberColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case lavender = "1", sage = "2", grape = "3", flamingo = "4", banana = "5",
         tangerine = "6", peacock = "7", graphite = "8", blueberry = "9",
         basil = "10", tomato = "11"

    var id: String { rawValue }
    var googleColorId: String { rawValue }
    var displayName: String { String(describing: self).capitalized }

    /// Google's own hex for this event color (what phones show).
    var googleHex: UInt32 {
        switch self {
        case .lavender: 0x7986CB
        case .sage: 0x33B679
        case .grape: 0x8E24AA
        case .flamingo: 0xE67C73
        case .banana: 0xF6BF26
        case .tangerine: 0xF4511E
        case .peacock: 0x039BE5
        case .graphite: 0x616161
        case .blueberry: 0x3F51B5
        case .basil: 0x0B8043
        case .tomato: 0xD50000
        }
    }

    init?(googleColorId: String?) {
        guard let googleColorId, let c = MemberColor(rawValue: googleColorId) else { return nil }
        self = c
    }
}
