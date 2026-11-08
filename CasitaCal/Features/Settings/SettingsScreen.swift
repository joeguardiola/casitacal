import SwiftUI

struct SettingsScreen: View {
    @Environment(MemberStore.self) private var members
    @State private var editing: Member?
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(members.members) { member in
                        Button {
                            editing = member
                        } label: {
                            HStack(spacing: 14) {
                                ProfileAvatar(member: member, size: 40)
                                VStack(alignment: .leading) {
                                    Text(member.name).font(.headline)
                                    Text("\(member.role.label) · \(member.color.displayName) in Google Calendar")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        offsets.map { members.members[$0] }.forEach(members.delete)
                    }
                    .onMove(perform: members.move)

                    Button("Add family member", systemImage: "plus.circle.fill") { isAdding = true }
                        .disabled(members.availableColors(for: nil).isEmpty)
                } header: {
                    Text("Family")
                } footer: {
                    Text("Each person owns one Google Calendar event color. To tag an event from your phone, set its color in the Google Calendar app.")
                }

                GoogleSettingsSection()

                CalendarPrefsSection()

                HouseholdSharingSection()

                if UIDevice.current.userInterfaceIdiom == .pad {
                    KitchenDisplaySection()
                }

                Section("About") {
                    LabeledContent("Version", value: AppVersion.display)
                    if let expiry = AppVersion.testFlightExpiry {
                        LabeledContent("TestFlight build good until", value: expiry.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { EditButton() }
            .sheet(item: $editing) { member in
                MemberEditor(member: member, isNew: false)
            }
            .sheet(isPresented: $isAdding) {
                MemberEditor(
                    member: Member(name: "", emoji: "🙂", color: members.availableColors(for: nil).first ?? .graphite),
                    isNew: true
                )
            }
        }
    }
}

struct MemberEditor: View {
    @Environment(MemberStore.self) private var members
    @Environment(\.dismiss) private var dismiss
    @State var member: Member
    let isNew: Bool

    @State private var nicknamesDraft: String?
    private var nicknamesText: Binding<String> {
        Binding(
            get: { nicknamesDraft ?? member.nicknames.joined(separator: ", ") },
            set: { nicknamesDraft = $0 }
        )
    }

    private let emojiChoices = ["🧔", "👩", "👨", "👱‍♀️", "🧒", "👧", "👦", "👶", "🐶", "🐱", "🙂", "⭐️"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ProfileAvatar(member: member, size: 96)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Name") {
                    TextField("Name", text: $member.name)
                        .textInputAutocapitalization(.words)
                    Picker("Role", selection: $member.role) {
                        ForEach(Member.Role.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    TextField("e.g. Dad, Papa", text: nicknamesText)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } header: {
                    Text("Also called")
                } footer: {
                    Text("Events with \(member.name.isEmpty ? "their name" : "“\(member.name)”") or any of these words in the title show up as theirs. Separate with commas.")
                }
                Section("Avatar") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(emojiChoices, id: \.self) { e in
                            Text(e)
                                .font(.system(size: 34))
                                .frame(width: 52, height: 52)
                                .background(Circle().fill(member.emoji == e ? member.color.soft : .clear))
                                .onTapGesture { member.emoji = e }
                        }
                    }
                }
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(members.availableColors(for: member)) { c in
                            Circle()
                                .fill(c.strong)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if member.color == c {
                                        Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { member.color = c }
                                .accessibilityLabel(c.displayName)
                        }
                    }
                } header: {
                    Text("Color")
                } footer: {
                    Text("Matches Google Calendar's “\(member.color.displayName)” event color.")
                }
            }
            .navigationTitle(isNew ? "New member" : member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        member.name = member.name.trimmingCharacters(in: .whitespaces)
                        if let nicknamesDraft {
                            member.nicknames = nicknamesDraft
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        }
                        members.upsert(member)
                        dismiss()
                    }
                    .disabled(member.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct GoogleSettingsSection: View {
    @Environment(GoogleAuth.self) private var auth
    @Environment(EventStore.self) private var store
    @State private var confirmSignOut = false

    var body: some View {
        Section {
            switch auth.state {
            case let .signedIn(email, _):
                LabeledContent("Account", value: email)
                NavigationLink {
                    Form { Section { CalendarPicker() } footer: {
                        Text("Only calendars you can edit are listed.")
                    } }
                    .navigationTitle("Family calendar")
                    .task { await store.loadCalendars() }
                } label: {
                    LabeledContent("Family calendar", value: store.selectedCalendar?.displayName ?? "Choose…")
                }
                if let synced = store.lastSynced {
                    LabeledContent("Last synced", value: synced.formatted(date: .omitted, time: .standard))
                }
                Button("Sign out", role: .destructive) { confirmSignOut = true }
                    .confirmationDialog("Sign out of Google?", isPresented: $confirmSignOut) {
                        Button("Sign out", role: .destructive) {
                            auth.signOut()
                            store.reset()
                        }
                    } message: {
                        Text("The iPad will stop showing your calendar until you sign in again.")
                    }
            default:
                LabeledContent("Account", value: "Not connected")
                Button("Sign in with Google", systemImage: "person.crop.circle.badge.checkmark") {
                    Task { await auth.signIn(); await store.loadCalendars() }
                }
            }
            if let error = auth.lastError ?? store.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Google Calendar")
        } footer: {
            Text("Sign-in is stored securely in the iPad's Keychain.")
        }
    }
}

struct CalendarPrefsSection: View {
    @AppStorage(Calendar.weekStartsOnMondayKey) private var weekStartsOnMonday = true

    var body: some View {
        Section("Calendar") {
            Picker("Week starts on", selection: $weekStartsOnMonday) {
                Text("Monday").tag(true)
                Text("Sunday").tag(false)
            }
        }
    }
}

struct KitchenDisplaySection: View {
    @Environment(KioskController.self) private var kiosk
    @Environment(PhotoLibrary.self) private var photos
    @Environment(WeatherStore.self) private var weather
    @State private var cameraRefused = false

    var body: some View {
        @Bindable var kiosk = kiosk
        Section {
            Picker("Photo slideshow when idle", selection: $kiosk.slideshowAfterMinutes) {
                Text("Off").tag(0)
                ForEach([2, 5, 10, 15, 30], id: \.self) { Text("After \($0) min").tag($0) }
            }
            LabeledContent("Slideshow album", value: photos.selectedAlbum?.title ?? "Choose in Photos")
            Toggle(isOn: Binding(
                get: { kiosk.presenceEnabled },
                set: { on in
                    if on { Task { cameraRefused = !(await kiosk.enablePresence()) } } else { kiosk.presenceEnabled = false }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wake when someone walks up")
                    Text("Front camera looks for a face during the slideshow. Nothing is recorded or saved.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if cameraRefused {
                Text("Camera access is off — turn it on in Settings → Apps → CasitaCal → Camera.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Toggle("Night clock at set hours", isOn: $kiosk.sleepEnabled)
            if kiosk.sleepEnabled {
                DatePicker("Dim at", selection: timeBinding($kiosk.sleepStart), displayedComponents: .hourAndMinute)
                DatePicker("Wake at", selection: timeBinding($kiosk.sleepEnd), displayedComponents: .hourAndMinute)
                HStack {
                    Image(systemName: "sun.min")
                    Slider(value: $kiosk.sleepBrightness, in: 0...0.4)
                    Image(systemName: "sun.max")
                }
            }
            Toggle("Night clock when the room is dark", isOn: $kiosk.darkRoomEnabled)
            if kiosk.darkRoomEnabled {
                LabeledContent("Light level now") {
                    Text("\(Int((kiosk.screenBrightness * 100).rounded()))% · \(kiosk.roomIsDark ? "dark" : "light")")
                        .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Counts as dark below \(Int((kiosk.darkThreshold * 100).rounded()))%")
                    Slider(value: $kiosk.darkThreshold, in: 0.03...0.5, step: 0.01)
                }
            }
            LabeledContent("Weather", value: weatherStatus)
        } header: {
            Text("Kitchen display")
        } footer: {
            Text("When the iPad sits untouched, it shows the photo slideshow — or the dark clock during your night hours or whenever the room is dark. A touch brings the calendar back (for 2 minutes at night). Dark-room detection reads the screen brightness, so keep Auto-Brightness on (Settings → Accessibility → Display & Text Size). Turn the lights off and watch “Light level now” to pick a good cut-off.")
        }
    }

    private var weatherStatus: String {
        switch weather.status {
        case .ready: weather.lastUpdated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "On"
        case .needsLocationPermission: "Tap the weather in the header"
        case .locationDenied: "Location is off"
        case let .unavailable(why): why
        case .idle: "—"
        }
    }

    private func timeBinding(_ comps: Binding<DateComponents>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: comps.wrappedValue) ?? .now },
            set: { comps.wrappedValue = Calendar.current.dateComponents([.hour, .minute], from: $0) }
        )
    }
}

/// "0.2.0 (202611080004)" — marketing version and build number (the upload time).
enum AppVersion {
    /// TestFlight builds stop opening 90 days after upload. The build number is the upload time
    /// (yyyyMMddHHmm), so the expiry can be worked out on the device. nil for non-TestFlight builds.
    static var testFlightExpiry: Date? {
        guard Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt",
              let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, build.count == 12 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyyMMddHHmm"
        return f.date(from: build).flatMap { Calendar.current.date(byAdding: .day, value: 90, to: $0) }
    }

    static var daysUntilExpiry: Int? {
        testFlightExpiry.map { Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0 }
    }

    static var display: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
