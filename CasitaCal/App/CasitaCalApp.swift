import SwiftUI

struct CasitaCalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var persistence: Persistence
    @State private var members: MemberStore
    @State private var chores: ChoreStore
    @State private var auth: GoogleAuth
    @State private var events: EventStore
    @State private var weather = WeatherStore()
    @State private var photos = PhotoLibrary()
    @State private var kiosk = KioskController()
    @State private var reminders = RemindersStore()
    @State private var daily = DailyInfoStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let persistence = Persistence.shared
        _persistence = State(initialValue: persistence)
        _members = State(initialValue: MemberStore(persistence: persistence))
        _chores = State(initialValue: ChoreStore(persistence: persistence))
        let auth = GoogleAuth()
        _auth = State(initialValue: auth)
        _events = State(initialValue: EventStore(auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.context)
                .environment(persistence)
                .environment(chores)
                .environment(members)
                .environment(auth)
                .environment(events)
                .environment(weather)
                .environment(photos)
                .environment(kiosk)
                .environment(reminders)
                .environment(daily)
                .onOpenURL { auth.handle(url: $0) }
                .task {
                    await auth.restore()
                    await events.loadCalendars()
                }
                .task { await weather.keepFresh() }
                .task {
                    // Kitchen-display behaviour (idle slideshow, night dimming, no auto-lock) is iPad-only.
                    guard UIDevice.current.userInterfaceIdiom == .pad else { return }
                    UIApplication.shared.isIdleTimerDisabled = true
                    await kiosk.start()
                }
                // Coming back to the app is activity: without this, the slideshow or night clock
                // covered the screen right away because the last touch was before it went away.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && UIDevice.current.userInterfaceIdiom == .pad { kiosk.registerInteraction() }
                }
        }
    }
}
