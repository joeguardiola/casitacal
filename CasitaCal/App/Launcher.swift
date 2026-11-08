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
#endif
