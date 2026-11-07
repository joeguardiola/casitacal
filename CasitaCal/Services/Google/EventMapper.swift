import Foundation

/// Decides which family members an event belongs to.
///
/// Priority:
/// 1. CasitaCal's hidden tag (`extendedProperties.shared.casitacal_members`): supports multiple people.
/// 2. Google event color (`colorId`): settable from any phone's Google Calendar app.
/// 3. Neither: the event is for everyone.
enum EventMapper {
    static func members(for event: CalendarEvent, from members: [Member]) -> [Member] {
        if !event.taggedMemberIDs.isEmpty {
            let tagged = event.taggedMemberIDs.compactMap { id in members.first { $0.id == id } }
            if !tagged.isEmpty { return tagged }
        }
        if let color = MemberColor(googleColorId: event.colorId),
           let owner = members.first(where: { $0.color == color }) {
            return [owner]
        }
        return []
    }

    /// Visible if it's an everyone-event, or at least one of its people is shown.
    static func isVisible(_ event: CalendarEvent, members: [Member], hidden: Set<Member.ID>) -> Bool {
        let owners = Self.members(for: event, from: members)
        return owners.isEmpty || owners.contains { !hidden.contains($0.id) }
    }
}
