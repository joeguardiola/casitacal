import SwiftUI

/// Entry point. Normally just CasitaCal; debug builds launched with `-cloudKitSchemaSetup YES`
/// instead run a one-off CloudKit schema setup that never opens the household database.
@main
enum Launcher {
    static func main() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "cloudKitSchemaSetup") {
            SchemaSetupApp.main()
            return
        }
        if UserDefaults.standard.bool(forKey: "wipeReleaseStore") {
            WipeReleaseStoreApp.main()
            return
        }
        #endif
        CasitaCalApp.main()
    }
}

#if DEBUG
/// Registers every record type CasitaCal uses — including the system `cloudkit.share` type that
/// family invites need — in the CloudKit *development* environment, using throwaway stores.
/// Afterwards: CloudKit Console → Deploy Schema Changes.
struct SchemaSetupApp: App {
    @State private var log: [String] = ["Registering CloudKit schema in Development…"]

    var body: some Scene {
        WindowGroup {
            List(log, id: \.self) { Text($0).font(.body.monospaced()) }
                .task {
                    let schema = Persistence.initializeCloudKitSchema()
                    print(schema); log.append(schema)
                    let share = await Persistence.registerShareSchema()
                    print(share); log.append(share)
                    log.append("Done. Now deploy the schema, then reinstall CasitaCal from TestFlight.")
                }
        }
    }
}

/// Deletes the TestFlight/App Store build's local household database (not the debug one, and
/// nothing in iCloud), so the next release launch downloads the household fresh from iCloud.
/// Settings and sign-ins are kept. For a device that ran debug builds against CloudKit
/// Development before they had their own file. Launch with `-wipeReleaseStore YES`.
struct WipeReleaseStoreApp: App {
    @State private var log: [String] = []

    var body: some Scene {
        WindowGroup {
            List(log, id: \.self) { Text($0).font(.body.monospaced()) }
                .task {
                    log = Self.wipe()
                    log.forEach { print($0) }
                }
        }
    }

    static func wipe() -> [String] {
        let fm = FileManager.default
        var dirs = [fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]] // pre–app group spot
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: Persistence.appGroupID) {
            dirs.append(group.appendingPathComponent("Library/Application Support", isDirectory: true))
        }
        var log: [String] = []
        for dir in dirs {
            let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in names where (name.hasPrefix("Household") || name.hasPrefix(".Household"))
                && !name.contains("HouseholdDebug") {
                do {
                    try fm.removeItem(at: dir.appendingPathComponent(name))
                    log.append("deleted \(name)")
                } catch {
                    log.append("FAILED \(name): \(error.localizedDescription)")
                }
            }
        }
        log.append(log.isEmpty ? "WIPE DONE: nothing to delete" : "WIPE DONE")
        return log
    }
}
#endif
