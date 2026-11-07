import SwiftUI

@main
struct CasitaCalApp: App {
    @State private var members = MemberStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(members)
                .onAppear {
                    // Kitchen display: never auto-lock while the app is open.
                    UIApplication.shared.isIdleTimerDisabled = true
                }
        }
    }
}
