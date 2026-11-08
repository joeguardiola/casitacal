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
    /// Shared folder so the Share extension can save into the same database (paid team only).
    static let appGroupID = "group.com.guardiola.casitacal"
    static var isExtension: Bool { Bundle.main.bundleURL.pathExtension == "appex" }
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
    @ObservationIgnored private var historyToken: NSPersistentHistoryToken?

    static var cloudKitEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "CASITACAL_HAS_ICLOUD") as? String == "YES"
    }

    /// Devices allowed to create the household on their own: the iPad, or any device when
    /// there's no iCloud (it's standalone then anyway).
    var isHouseholdHost: Bool { !usesCloudKit || UIDevice.current.userInterfaceIdiom == .pad }

    init(inMemory: Bool = false, cloudKit: Bool = Persistence.cloudKitEnabled) {
        usesCloudKit = cloudKit && !inMemory
        container = NSPersistentCloudKitContainer(name: "CasitaCal", managedObjectModel: CasitaModel.shared)

        let dir = Self.storeDirectory()

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
        context.transactionAuthor = Self.isExtension ? Self.extensionAuthor : "app"

        if !inMemory {
            historyToken = try? coordinator.currentPersistentHistoryToken(fromStores: nil)
            remoteObserver = NotificationCenter.default.addObserver(
                forName: .NSPersistentStoreRemoteChange, object: coordinator, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.mergeChangesFromExtension()
                    self?.revision += 1
                }
            }
        }
    }

    static let extensionAuthor = "share-extension"

    /// Creates every record type in the CloudKit *development* schema (using a throwaway store),
    /// so the whole schema can be deployed to production before TestFlight/App Store builds.
    /// Run with the launch argument `-initializeCloudKitSchema YES` on a development build.
    static func initializeCloudKitSchema() -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SchemaInit-\(UUID().uuidString).sqlite")
        let container = NSPersistentCloudKitContainer(name: "CasitaCalSchema", managedObjectModel: CasitaModel.shared)
        let d = NSPersistentStoreDescription(url: url)
        d.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        d.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        d.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerID)
        container.persistentStoreDescriptions = [d]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { return "SCHEMA INIT FAILED (load): \(loadError)" }
        do {
            try container.initializeCloudKitSchema(options: [])
            return "SCHEMA INIT OK: \(CasitaModel.shared.entities.compactMap(\.name).joined(separator: ", "))"
        } catch {
            return "SCHEMA INIT FAILED: \(error)"
        }
    }

    /// Waits (up to `timeout`) for the next successful iCloud upload. The Share extension uses this
    /// so a recipe added from Safari reaches the kitchen iPad without opening CasitaCal first.
    func waitForExport(timeout: Duration = .seconds(10)) async {
        guard usesCloudKit else { return }
        let start = Date()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await note in NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification) {
                    guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                            as? NSPersistentCloudKitContainer.Event else { continue }
                    if event.type == .export, let end = event.endDate, end > start { return }
                }
            }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
    }

    /// Saves made by the Share extension (another process) aren't merged automatically.
    private func mergeChangesFromExtension() {
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: historyToken)
        guard let result = try? context.execute(request) as? NSPersistentHistoryResult,
              let transactions = result.result as? [NSPersistentHistoryTransaction], !transactions.isEmpty
        else { return }
        for t in transactions where t.author == Self.extensionAuthor {
            context.mergeChanges(fromContextDidSave: t.objectIDNotification())
        }
        historyToken = transactions.last?.token
    }

    /// The database folder: the App Group container when available (so the Share extension can
    /// use it), otherwise Application Support. Moves an existing database over the first time.
    static func storeDirectory() -> URL {
        let fm = FileManager.default
        let legacy = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        guard let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            try? fm.createDirectory(at: legacy, withIntermediateDirectories: true)
            return legacy
        }
        let dir = group.appendingPathComponent("Library/Application Support", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // One-time move (app only; the database must not be open yet). Includes the SQLite
        // sidecar files and Core Data's external-data folders so CloudKit sync state comes along.
        if !isExtension, !fm.fileExists(atPath: dir.appendingPathComponent("Household.sqlite").path),
           let items = try? fm.contentsOfDirectory(atPath: legacy.path) {
            for name in items where name.hasPrefix("Household") || name.hasPrefix(".Household") || name == "ckAssetFiles" {
                try? fm.moveItem(at: legacy.appendingPathComponent(name), to: dir.appendingPathComponent(name))
            }
        }
        return dir
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
