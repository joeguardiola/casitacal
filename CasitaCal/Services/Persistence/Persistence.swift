import CoreData
import Foundation

/// The household database (members, chores, lists, meals).
///
/// Today it's stored on the device only. When the paid Apple team is set up
/// (`CASITACAL_HAS_ICLOUD = YES`), the same store syncs through CloudKit. History
/// tracking is on from day one so existing data uploads when that happens.
@MainActor
final class Persistence {
    static let cloudKitContainerID = "iCloud.com.guardiola.casitacal"

    let container: NSPersistentCloudKitContainer
    var context: NSManagedObjectContext { container.viewContext }
    let usesCloudKit: Bool

    static var cloudKitEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "CASITACAL_HAS_ICLOUD") as? String == "YES"
    }

    init(inMemory: Bool = false, cloudKit: Bool = Persistence.cloudKitEnabled) {
        usesCloudKit = cloudKit && !inMemory
        container = NSPersistentCloudKitContainer(name: "CasitaCal", managedObjectModel: CasitaModel.shared)

        let description: NSPersistentStoreDescription
        if inMemory {
            description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            description = NSPersistentStoreDescription(url: dir.appendingPathComponent("Household.sqlite"))
        }
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.cloudKitContainerOptions = usesCloudKit
            ? NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerID)
            : nil
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error { assertionFailure("Household store failed to load: \(error)") }
        }
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
    }

    /// The one household record everything hangs off (created on first launch).
    func household() -> CDHousehold {
        let request = NSFetchRequest<CDHousehold>(entityName: "CDHousehold")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        if let existing = try? context.fetch(request).first { return existing }
        let h = CDHousehold(context: context)
        h.id = UUID()
        h.name = "Our casita"
        h.createdAt = Date()
        save()
        return h
    }

    func save() {
        guard context.hasChanges else { return }
        do { try context.save() } catch {
            assertionFailure("Save failed: \(error)")
            context.rollback()
        }
    }

    /// Default lists so the Lists screen isn't empty on first launch.
    func seedListsIfNeeded() {
        let request = NSFetchRequest<CDList>(entityName: "CDList")
        guard (try? context.count(for: request)) == 0 else { return }
        let h = household()
        for (i, (emoji, title)) in [("🛒", "Groceries"), ("✅", "To-do")].enumerated() {
            let l = CDList(context: context)
            l.id = UUID()
            l.title = title
            l.emoji = emoji
            l.sortOrder = Int16(i)
            l.createdAt = Date()
            l.household = h
        }
        save()
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

/// Lets SwiftUI views reach the household database through the environment.
@MainActor
@Observable
final class HouseholdData {
    @ObservationIgnored let persistence: Persistence
    init(_ persistence: Persistence) { self.persistence = persistence }
}
