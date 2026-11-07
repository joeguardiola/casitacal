import Foundation

/// Decides which family members an event belongs to.
///
/// Checked in order:
/// 1. CasitaCal's multi-person tag (`extendedProperties.shared.casitacal_members`).
/// 2. Google event color (`colorId`): settable from any phone's Google Calendar app.
/// 3. A person's name or nickname in the title ("Emma soccer", "Joe's dentist").
/// 4. None of the above: the event is for everyone.
enum EventMapper {
    enum Source: Equatable {
        case tag, color, title, none

        var explanation: String? {
            switch self {
            case .tag: "Assigned in CasitaCal"
            case .color: "Matched by event color"
            case .title: "Matched by name in the title"
            case .none: nil
            }
        }
    }

    struct Assignment: Equatable {
        var members: [Member]
        var source: Source
    }

    static func assignment(for event: CalendarEvent, from members: [Member]) -> Assignment {
        if !event.taggedMemberIDs.isEmpty {
            let tagged = event.taggedMemberIDs.compactMap { id in members.first { $0.id == id } }
            if !tagged.isEmpty { return Assignment(members: tagged, source: .tag) }
        }
        if let color = MemberColor(googleColorId: event.colorId),
           let owner = members.first(where: { $0.color == color }) {
            return Assignment(members: [owner], source: .color)
        }
        let named = members.filter { titleMentions(event.title, member: $0) }
        if !named.isEmpty { return Assignment(members: named, source: .title) }
        return Assignment(members: [], source: .none)
    }

    static func members(for event: CalendarEvent, from members: [Member]) -> [Member] {
        assignment(for: event, from: members).members
    }

    /// Visible if it's an everyone-event, or at least one of its people is shown.
    static func isVisible(_ event: CalendarEvent, members: [Member], hidden: Set<Member.ID>) -> Bool {
        let owners = Self.members(for: event, from: members)
        return owners.isEmpty || owners.contains { !hidden.contains($0.id) }
    }

    /// Whole-word, case- and accent-insensitive match. "Joe's" matches Joe; "Joey" does not.
    static func titleMentions(_ title: String, member: Member) -> Bool {
        let haystack = fold(title)
        return member.titleKeywords.contains { keyword in
            let needle = NSRegularExpression.escapedPattern(for: fold(keyword))
            let pattern = "(?<![\\p{L}\\p{N}])\(needle)(?![\\p{L}\\p{N}])"
            return haystack.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
