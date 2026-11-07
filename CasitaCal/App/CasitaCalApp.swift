import SwiftUI

@main
struct CasitaCalApp: App {
    @State private var members = MemberStore()
    @State private var auth: GoogleAuth
    @State private var events: EventStore

    init() {
        let auth = GoogleAuth()
        _auth = State(initialValue: auth)
        _events = State(initialValue: EventStore(auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(members)
                .environment(auth)
                .environment(events)
                .onOpenURL { auth.handle(url: $0) }
                .task {
                    await auth.restore()
                    await events.loadCalendars()
                }
                .onAppear {
                    // Kitchen display: never auto-lock while the app is open.
                    UIApplication.shared.isIdleTimerDisabled = true
                }
        }
    }
}
