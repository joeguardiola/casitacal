import CoreData
import Foundation
import Observation

/// Family members, stored in the household database (syncs via iCloud once enabled).
/// Which members are hidden in the avatar filter is per-device and stays local.
@MainActor
@Observable
final class MemberStore {
    private(set) var members: [Member] = []
    /// Members whose items are hidden by the avatar filter row (this device only).
    var hiddenMemberIDs: Set<Member.ID> = []

    private let persistence: Persistence
    private let defaults: UserDefaults
    @ObservationIgnored private var observer: NSObjectProtocol?
    /// Where Milestone 1–4 builds kept members.
    static let legacyKey = "casitacal.members.v1"

    init(persistence: Persistence, defaults: UserDefaults = .standard) {
        self.persistence = persistence
        self.defaults = defaults
        migrateOrSeedIfNeeded()
        reload()
        // Pick up edits from other devices (CloudKit merges into the view context).
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange, object: persistence.context, queue: .main
        ) { [weak self] note in
            let touchesMembers = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey]
                .contains { ((note.userInfo?[$0] as? Set<NSManagedObject>) ?? []).contains { $0 is CDMember } }
            guard touchesMembers else { return }
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func isVisible(_ member: Member) -> Bool { !hiddenMemberIDs.contains(member.id) }

    func toggleVisibility(_ member: Member) {
        if hiddenMemberIDs.contains(member.id) { hiddenMemberIDs.remove(member.id) } else { hiddenMemberIDs.insert(member.id) }
    }

    func upsert(_ member: Member) {
        let row = fetch(member.id) ?? {
            let r = persistence.insert(CDMember.self)
            r.id = member.id
            r.sortOrder = Int16(members.count)
            r.household = persistence.household()
            return r
        }()
        apply(member, to: row)
        persistence.save()
        reload()
    }

    func delete(_ member: Member) {
        if let row = fetch(member.id) { persistence.context.delete(row) }
        hiddenMemberIDs.remove(member.id)
        persistence.save()
        reload()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        var reordered = members
        reordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for (i, m) in reordered.enumerated() { fetch(m.id)?.sortOrder = Int16(i) }
        persistence.save()
        reload()
    }

    func member(id: Member.ID) -> Member? { members.first { $0.id == id } }

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

    // MARK: - Storage

    private func reload() {
        let request = NSFetchRequest<CDMember>(entityName: "CDMember")
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true),
                                   NSSortDescriptor(key: "name", ascending: true)]
        // Only the household in use: a stray second household must not show up as duplicate people.
        if let household = persistence.activeHousehold {
            request.predicate = NSPredicate(format: "household == %@ OR household == nil", household)
        }
        let rows = (try? persistence.context.fetch(request)) ?? []
        // CloudKit can briefly deliver duplicates of the same member; show each id once.
        var seen = Set<UUID>()
        members = rows.compactMap(Self.member(from:)).filter { seen.insert($0.id).inserted }
    }

    private func fetch(_ id: UUID) -> CDMember? {
        let request = NSFetchRequest<CDMember>(entityName: "CDMember")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? persistence.context.fetch(request).first
    }

    private func apply(_ m: Member, to row: CDMember) {
        row.name = m.name
        row.emoji = m.emoji
        row.colorId = m.color.googleColorId
        row.role = m.role.rawValue
        row.nicknames = m.nicknames.joined(separator: ",")
    }

    private static func member(from row: CDMember) -> Member? {
        guard let id = row.id, let name = row.name, let color = MemberColor(googleColorId: row.colorId) else { return nil }
        return Member(
            id: id, name: name, emoji: row.emoji ?? "", color: color,
            role: Member.Role(rawValue: row.role ?? "") ?? .adult,
            nicknames: (row.nicknames ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
        )
    }

    /// First run on the new database: bring over members from older builds (same IDs,
    /// so Google events tagged with them still match), or start with a placeholder family.
    private func migrateOrSeedIfNeeded() {
        guard persistence.isHouseholdHost else { return } // phones get members from the household
        if persistence.usesCloudKit {
            // A fresh install on the kitchen iPad must not start its own household while the real
            // one is still downloading (that once added a second "Our casita" with a placeholder
            // family). Seed only once iCloud has answered and there's still nobody.
            Task { @MainActor [weak self] in
                guard let self, await self.persistence.waitForFirstDownload() else { return }
                self.seedIfEmpty()
                self.reload()
            }
            return
        }
        seedIfEmpty()
    }

    private func seedIfEmpty() {
        let request = NSFetchRequest<CDMember>(entityName: "CDMember")
        guard (try? persistence.context.count(for: request)) == 0 else { return }
        let legacy = defaults.data(forKey: Self.legacyKey).flatMap { try? JSONDecoder().decode([Member].self, from: $0) }
        let household = persistence.household()
        for (i, m) in (legacy ?? Self.starterFamily).enumerated() {
            let row = persistence.insert(CDMember.self)
            row.id = m.id
            row.sortOrder = Int16(i)
            row.household = household
            apply(m, to: row)
        }
        persistence.save()
        if legacy != nil { defaults.removeObject(forKey: Self.legacyKey) }
    }

    /// Placeholder family so the dashboard isn't empty on first launch. Edit in Settings.
    static let starterFamily: [Member] = [
        Member(name: "Joe", emoji: "🧔", color: .peacock, role: .adult),
        Member(name: "Mom", emoji: "👩", color: .grape, role: .adult),
        Member(name: "Kid 1", emoji: "🧒", color: .sage, role: .kid),
        Member(name: "Kid 2", emoji: "👧", color: .tangerine, role: .kid),
    ]
}
