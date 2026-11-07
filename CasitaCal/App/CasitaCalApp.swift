import SwiftUI

@main
struct CasitaCalApp: App {
    @State private var members = MemberStore()
    @State private var auth: GoogleAuth
    @State private var events: EventStore
    @State private var weather = WeatherStore()
    @State private var photos = PhotoLibrary()
    @State private var kiosk = KioskController()

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
                .environment(weather)
                .environment(photos)
                .environment(kiosk)
                .onOpenURL { auth.handle(url: $0) }
                .task {
                    await auth.restore()
                    await events.loadCalendars()
                }
                .task { await weather.keepFresh() }
                .task { await kiosk.start() }
                .onAppear {
                    // Kitchen display: never auto-lock while the app is open.
                    UIApplication.shared.isIdleTimerDisabled = true
                }
        }
    }
}
