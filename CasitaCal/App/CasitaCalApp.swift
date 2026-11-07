import SwiftUI

@main
struct CasitaCalApp: App {
    private let persistence: Persistence
    @State private var household: HouseholdData
    @State private var members: MemberStore
    @State private var chores: ChoreStore
    @State private var auth: GoogleAuth
    @State private var events: EventStore
    @State private var weather = WeatherStore()
    @State private var photos = PhotoLibrary()
    @State private var kiosk = KioskController()

    init() {
        let persistence = Persistence()
        persistence.seedListsIfNeeded()
        self.persistence = persistence
        _household = State(initialValue: HouseholdData(persistence))
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
                .environment(household)
                .environment(chores)
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
