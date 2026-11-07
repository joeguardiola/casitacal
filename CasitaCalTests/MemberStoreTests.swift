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

    @Test func seedsStarterFamilyOnFirstLaunch() {
        let store = MemberStore(defaults: freshDefaults())
        #expect(store.members.count == MemberStore.starterFamily.count)
    }

    @Test func persistsAcrossInstances() {
        let d = freshDefaults()
        let store = MemberStore(defaults: d)
        store.upsert(Member(name: "Grandma", emoji: "👵", color: .banana))
        let reloaded = MemberStore(defaults: d)
        #expect(reloaded.members.contains { $0.name == "Grandma" && $0.color == .banana })
    }

    @Test func mapsGoogleColorIdToMember() {
        let store = MemberStore(defaults: freshDefaults())
        let joe = store.members.first { $0.name == "Joe" }!
        #expect(store.member(forGoogleColorId: joe.color.googleColorId)?.id == joe.id)
        #expect(store.member(forGoogleColorId: nil) == nil)
        #expect(store.member(forGoogleColorId: "99") == nil)
    }

    @Test func colorsAreUniquePerMember() {
        let store = MemberStore(defaults: freshDefaults())
        let available = store.availableColors(for: nil)
        for m in store.members { #expect(!available.contains(m.color)) }
        let joe = store.members[0]
        #expect(store.availableColors(for: joe).contains(joe.color))
    }

    @Test func toggleVisibility() {
        let store = MemberStore(defaults: freshDefaults())
        let m = store.members[0]
        store.toggleVisibility(m)
        #expect(!store.isVisible(m))
        store.toggleVisibility(m)
        #expect(store.isVisible(m))
    }
}
