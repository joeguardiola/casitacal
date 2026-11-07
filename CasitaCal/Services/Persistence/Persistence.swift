import CloudKit
import CoreData
import Foundation
import Observation
import UIKit

/// The household database (members, chores, lists, meals).
///
/// - Without iCloud (free Apple team): one local store.
/// - With iCloud (`CASITACAL_HAS_ICLOUD = YES`, paid team): two CloudKit-mirrored stores.
///   - **private**: data this Apple ID owns. The kitchen iPad and a phone on the same Apple ID
///     sync through it automatically.
///   - **shared**: households other Apple IDs have shared with us (e.g. a spouse's phone).
///
/// The kitchen iPad *hosts* the household and shares it; phones never create one on their own,
/// so nothing gets duplicated while the first sync is still downloading.
@MainActor
@Observable
final class Persistence {
    static let cloudKitContainerID = "iCloud.com.guardiola.casitacal"
    static let shared = Persistence()

    @ObservationIgnored let container: NSPersistentCloudKitContainer
    var context: NSManagedObjectContext { container.viewContext }
    @ObservationIgnored let usesCloudKit: Bool
    @ObservationIgnored private(set) var privateStore: NSPersistentStore?
    @ObservationIgnored private(set) var sharedStore: NSPersistentStore?

    /// Bumped whenever the active household may have changed (remote import, share accepted).
    private(set) var revision = 0
    private(set) var lastShareError: String?

    @ObservationIgnored private var remoteObserver: NSObjectProtocol?

    static var cloudKitEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "CASITACAL_HAS_ICLOUD") as? String == "YES"
    }

    /// Devices allowed to create the household on their own: the iPad, or any device when
    /// there's no iCloud (it's standalone then anyway).
    var isHouseholdHost: Bool { !usesCloudKit || UIDevice.current.userInterfaceIdiom == .pad }

    init(inMemory: Bool = false, cloudKit: Bool = Persistence.cloudKitEnabled) {
        usesCloudKit = cloudKit && !inMemory
        container = NSPersistentCloudKitContainer(name: "CasitaCal", managedObjectModel: CasitaModel.shared)

        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        func describe(_ url: URL, scope: CKDatabase.Scope?) -> NSPersistentStoreDescription {
            let d = NSPersistentStoreDescription(url: url)
            d.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            d.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            if let scope {
                let options = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerID)
                options.databaseScope = scope
                d.cloudKitContainerOptions = options
            }
            return d
        }

        let privateURL = inMemory ? URL(fileURLWithPath: "/dev/null") : dir.appendingPathComponent("Household.sqlite")
        var descriptions = [describe(privateURL, scope: usesCloudKit ? .private : nil)]
        if usesCloudKit {
            descriptions.append(describe(dir.appendingPathComponent("Household-shared.sqlite"), scope: .shared))
        }
        container.persistentStoreDescriptions = descriptions

        container.loadPersistentStores { _, error in
            if let error { assertionFailure("Household store failed to load: \(error)") }
        }
        let coordinator = container.persistentStoreCoordinator
        privateStore = coordinator.persistentStore(for: privateURL) ?? coordinator.persistentStores.first
        if usesCloudKit {
            sharedStore = coordinator.persistentStore(for: dir.appendingPathComponent("Household-shared.sqlite"))
        }

        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        if usesCloudKit {
            remoteObserver = NotificationCenter.default.addObserver(
                forName: .NSPersistentStoreRemoteChange, object: coordinator, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.revision += 1 }
            }
        }
    }

    // MARK: - Household

    /// The household this device shows: one shared with us wins over our own.
    var activeHousehold: CDHousehold? {
        _ = revision
        let request = NSFetchRequest<CDHousehold>(entityName: "CDHousehold")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let all = (try? context.fetch(request)) ?? []
        return all.first { $0.objectID.persistentStore == sharedStore && sharedStore != nil } ?? all.first
    }

    var hasHousehold: Bool { activeHousehold != nil }

    /// The active household, creating it if this device is allowed to.
    func household() -> CDHousehold {
        if let h = activeHousehold { return h }
        return createHousehold()
    }

    @discardableResult
    func createHousehold(name: String = "Our casita") -> CDHousehold {
        let h = CDHousehold(context: context)
        if let privateStore { context.assign(h, to: privateStore) }
        h.id = UUID()
        h.name = name
        h.createdAt = Date()
        save()
        revision += 1
        return h
    }

    /// Insert a new row in the same store as the household (required for sharing:
    /// related objects must live in the same store and CloudKit zone).
    func insert<T: NSManagedObject>(_ type: T.Type) -> T {
        let object = NSEntityDescription.insertNewObject(forEntityName: String(describing: T.self), into: context) as! T
        if let store = activeHousehold?.objectID.persistentStore ?? privateStore {
            context.assign(object, to: store)
        }
        return object
    }

    func save() {
        guard context.hasChanges else { return }
        do { try context.save() } catch {
            assertionFailure("Save failed: \(error)")
            context.rollback()
        }
    }

    /// Default lists so the Lists screen isn't empty on first launch (host device only).
    func seedListsIfNeeded() {
        guard isHouseholdHost else { return }
        let request = NSFetchRequest<CDList>(entityName: "CDList")
        guard (try? context.count(for: request)) == 0 else { return }
        let h = household()
        for (i, (emoji, title)) in [("🛒", "Groceries"), ("✅", "To-do")].enumerated() {
            let l = insert(CDList.self)
            l.id = UUID()
            l.title = title
            l.emoji = emoji
            l.sortOrder = Int16(i)
            l.createdAt = Date()
            l.household = h
        }
        save()
    }

    // MARK: - Sharing (needs iCloud)

    /// True when this device sees the household through someone else's share.
    var isParticipant: Bool {
        guard let store = activeHousehold?.objectID.persistentStore, let sharedStore else { return false }
        return store == sharedStore
    }

    func existingShare() -> CKShare? {
        guard usesCloudKit, let h = activeHousehold else { return nil }
        return (try? container.fetchShares(matching: [h.objectID]))?[h.objectID]
    }

    /// The household's share, creating it the first time. Everything related to the
    /// household (members, chores, lists, meals) moves into the shared zone with it.
    func shareForHousehold() async throws -> CKShare {
        if let existing = existingShare() { return existing }
        let h = household()
        save()
        let (_, share, _) = try await container.share([h], to: nil)
        share[CKShare.SystemFieldKey.title] = "CasitaCal · \(h.name ?? "Our casita")"
        revision += 1
        return share
    }

    var cloudKitContainer: CKContainer { CKContainer(identifier: Self.cloudKitContainerID) }

    func persistUpdatedShare(_ share: CKShare) {
        guard let privateStore else { return }
        container.persistUpdatedShare(share, in: privateStore) { _, error in
            if let error { print("persistUpdatedShare failed: \(error)") }
        }
    }

    /// Called when someone taps an invite link on this device.
    func acceptShare(_ metadata: CKShare.Metadata) async {
        guard let sharedStore else {
            lastShareError = "iCloud sync isn't turned on in this build."
            return
        }
        do {
            try await container.acceptShareInvitations(from: [metadata], into: sharedStore)
            lastShareError = nil
            revision += 1
        } catch {
            lastShareError = "Couldn't join the household: \(error.localizedDescription)"
        }
    }
}

/// "yyyy-MM-dd" keys for calendar days (same meaning on every device).
enum DayKey {
    static func from(_ date: Date, calendar: Calendar = .app) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(_ key: String, calendar: Calendar = .app) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
}
