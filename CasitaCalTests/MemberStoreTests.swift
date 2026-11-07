import Testing
import Foundation
@testable import CasitaCal

@MainActor
struct MemberStoreTests {
    private func freshDefaults() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func store(_ p: Persistence = Persistence(inMemory: true), defaults: UserDefaults? = nil) -> MemberStore {
        MemberStore(persistence: p, defaults: defaults ?? freshDefaults())
    }

    @Test func seedsStarterFamilyOnFirstLaunch() {
        #expect(store().members.count == MemberStore.starterFamily.count)
    }

    @Test func persistsInDatabase() {
        let p = Persistence(inMemory: true)
        let s = store(p)
        s.upsert(Member(name: "Grandma", emoji: "👵", color: .banana, nicknames: ["Nana"]))
        let reloaded = store(p)
        #expect(reloaded.members.contains { $0.name == "Grandma" && $0.color == .banana && $0.nicknames == ["Nana"] })
    }

    @Test func migratesLegacyMembersKeepingIDs() throws {
        let d = freshDefaults()
        let legacy = [Member(name: "Emma", emoji: "👧", color: .sage, role: .kid)]
        d.set(try JSONEncoder().encode(legacy), forKey: MemberStore.legacyKey)
        let s = store(defaults: d)
        #expect(s.members.map(\.id) == legacy.map(\.id))
        #expect(d.data(forKey: MemberStore.legacyKey) == nil)
    }

    @Test func reorderAndDelete() {
        let s = store()
        let first = s.members[0]
        s.move(fromOffsets: [0], toOffset: s.members.count)
        #expect(s.members.last?.id == first.id)
        s.delete(first)
        #expect(!s.members.contains { $0.id == first.id })
    }

    @Test func mapsGoogleColorIdToMember() {
        let s = store()
        let joe = s.members.first { $0.name == "Joe" }!
        #expect(s.member(forGoogleColorId: joe.color.googleColorId)?.id == joe.id)
        #expect(s.member(forGoogleColorId: nil) == nil)
        #expect(s.member(forGoogleColorId: "99") == nil)
    }

    @Test func colorsAreUniquePerMember() {
        let s = store()
        let available = s.availableColors(for: nil)
        for m in s.members { #expect(!available.contains(m.color)) }
        #expect(s.availableColors(for: s.members[0]).contains(s.members[0].color))
    }

    @Test func toggleVisibility() {
        let s = store()
        let m = s.members[0]
        s.toggleVisibility(m)
        #expect(!s.isVisible(m))
        s.toggleVisibility(m)
        #expect(s.isVisible(m))
    }
}
