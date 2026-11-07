import Foundation
import Observation

/// Local (on-device) member storage for Milestone 1.
/// Milestone 5 moves members into the shared iCloud household.
@MainActor
@Observable
final class MemberStore {
    private(set) var members: [Member] = []
    /// Members whose items are currently shown (the avatar filter row). Empty = everyone.
    var hiddenMemberIDs: Set<Member.ID> = []

    private let defaults: UserDefaults
    private let key = "casitacal.members.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func isVisible(_ member: Member) -> Bool { !hiddenMemberIDs.contains(member.id) }

    func toggleVisibility(_ member: Member) {
        if hiddenMemberIDs.contains(member.id) {
            hiddenMemberIDs.remove(member.id)
        } else {
            hiddenMemberIDs.insert(member.id)
        }
    }

    func upsert(_ member: Member) {
        if let i = members.firstIndex(where: { $0.id == member.id }) {
            members[i] = member
        } else {
            members.append(member)
        }
        save()
    }

    func delete(_ member: Member) {
        members.removeAll { $0.id == member.id }
        hiddenMemberIDs.remove(member.id)
        save()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        members.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save()
    }

    /// The member who owns a Google event color, if any.
    func member(forGoogleColorId colorId: String?) -> Member? {
        guard let color = MemberColor(googleColorId: colorId) else { return nil }
        return members.first { $0.color == color }
    }

    /// Colors not yet claimed by another member (each color maps to exactly one person).
    func availableColors(for member: Member?) -> [MemberColor] {
        let taken = Set(members.filter { $0.id != member?.id }.map(\.color))
        return MemberColor.allCases.filter { !taken.contains($0) }
    }

    private func load() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Member].self, from: data) {
            members = decoded
        } else {
            members = Self.starterFamily
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(members) {
            defaults.set(data, forKey: key)
        }
    }

    /// Placeholder family so the dashboard isn't empty on first launch. Edit in Settings.
    static let starterFamily: [Member] = [
        Member(name: "Joe", emoji: "🧔", color: .peacock, role: .adult),
        Member(name: "Mom", emoji: "👩", color: .grape, role: .adult),
        Member(name: "Kid 1", emoji: "🧒", color: .sage, role: .kid),
        Member(name: "Kid 2", emoji: "👧", color: .tangerine, role: .kid),
    ]
}
