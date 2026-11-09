import SwiftUI

struct CalendarScreen: View {
    @Environment(GoogleAuth.self) private var auth
    @Environment(EventStore.self) private var store
    @Environment(MemberStore.self) private var memberStore
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("calendar.mode") private var storedMode: CalendarMode = .week
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
    /// Phones only get Schedule (Week/Month need iPad width).
    private var mode: CalendarMode { isCompact ? .schedule : storedMode }
    /// Picker binding that shows the effective mode.
    private var modeBinding: Binding<CalendarMode> {
        Binding(get: { mode }, set: { new in withAnimation(.snappy) { storedMode = new } })
    }
    @AppStorage("calendar.weekDayCount") private var weekDayCount = CalendarRanges.defaultRollingDayCount
    // Observed so the views redraw when the week-start setting changes.
    @AppStorage(Calendar.weekStartsOnMondayKey) private var weekStartsOnMonday = true
    /// The leftmost day in Week; otherwise the date the view is built around.
    @State private var anchor = Date()
    @State private var pageEdge: Edge = .trailing
    @Environment(KioskController.self) private var kiosk
    @State private var selected: CalendarEvent?
    @State private var isAdding = false

    private var range: DateInterval {
        mode == .week
            ? CalendarRanges.rollingRange(from: anchor, count: weekDayCount)
            : CalendarRanges.range(for: mode, anchor: anchor)
    }

    private var isConnected: Bool { auth.state != .signedOut && store.selectedCalendarId != nil }

    private var visibleEvents: [CalendarEvent] {
        store.events.filter {
            EventMapper.isVisible($0, members: memberStore.members, hidden: memberStore.hiddenMemberIDs)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            toolbar
            PagedContent(key: Calendar.app.startOfDay(for: anchor), edge: pageEdge) { content }
                .swipeToPage(isEnabled: isConnected, previous: { page(-1) }, next: { page(1) })
        }
        .padding(isCompact ? 14 : 24)
        .onChange(of: kiosk.wakeCount) { anchor = Date() } // back to today after the slideshow
        .modifier(FollowsToday(anchor: $anchor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas)
        // Reload when the range or calendar changes, then every 60s while visible & active.
        .task(id: TaskKey(range: range, calendarId: store.selectedCalendarId, active: scenePhase == .active && auth.isSignedIn)) {
            guard scenePhase == .active, auth.isSignedIn else { return }
            await store.keepFresh(range)
        }
        .sheet(item: $selected) { e in
            EventDetailSheet(event: e)
        }
        .sheet(isPresented: $isAdding) {
            AddEventSheet(day: defaultAddDay)
        }
        .overlay(alignment: .bottomTrailing) {
            if auth.isSignedIn && store.selectedCalendarId != nil {
                Button { isAdding = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(Circle().fill(Palette.accent))
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                }
                .padding(28)
                .accessibilityLabel("Add event")
            }
        }
    }

    /// The day new events default to: the day being viewed, or today if it's on screen.
    private var defaultAddDay: Date {
        return range.contains(Date()) ? Date() : range.start
    }

    private struct TaskKey: Equatable {
        let range: DateInterval
        let calendarId: String?
        let active: Bool
    }

    @ViewBuilder
    private var content: some View {
        // While Google sign-in is being restored (.unknown), show cached events instead of the sign-in card.
        if !isConnected {
            GoogleConnectCard()
                .frame(maxWidth: 560)
                .frame(maxHeight: .infinity)
        } else {
            switch mode {
            case .week:
                WeekView(days: CalendarRanges.days(in: range), events: visibleEvents, members: memberStore.members,
                         onSelect: { selected = $0 })
            case .month:
                MonthView(anchor: anchor, days: CalendarRanges.monthGrid(for: anchor), events: visibleEvents,
                          members: memberStore.members, onOpenDay: openDay)
            case .schedule:
                ScheduleView(days: CalendarRanges.days(in: range), events: visibleEvents, members: memberStore.members) { selected = $0 }
            }
        }
    }

    /// Month cells open the rolling week starting on that day.
    private func openDay(_ day: Date) {
        withAnimation(.snappy) {
            anchor = day
            storedMode = .week
        }
    }

    private func page(_ n: Int) {
        pageEdge = n > 0 ? .trailing : .leading
        // Separate update so the outgoing page also slides the new direction.
        Task { @MainActor in
            withAnimation(.snappy) {
                anchor = mode == .week
                    ? CalendarRanges.stepRolling(anchor, count: weekDayCount, by: n)
                    : CalendarRanges.step(anchor, mode: mode, by: n)
            }
        }
    }

    private func goToToday() {
        let now = Date()
        pageEdge = now < anchor ? .leading : .trailing
        Task { @MainActor in
            withAnimation(.snappy) { anchor = now }
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        if isCompact { compactToolbar } else { regularToolbar }
    }

    private var compactToolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                navButton("chevron.left", label: "Previous") { page(-1) }
                Text(title)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                Button("Today", action: goToToday)
                    .buttonStyle(.bordered)
                navButton("chevron.right", label: "Next") { page(1) }
            }
            syncStatus
        }
    }

    /// One row when everything fits (iPad landscape), two tidy rows when it doesn't (iPad portrait).
    private var regularToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                dateControls
                Spacer(minLength: 8)
                syncStatus
                daysPicker
                viewPicker
            }
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    dateControls
                    Spacer(minLength: 8)
                    syncStatus
                }
                HStack(spacing: 14) {
                    daysPicker
                    Spacer(minLength: 8)
                    viewPicker
                }
            }
        }
    }

    private var dateControls: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                navButton("chevron.left", label: "Previous") { page(-1) }
                navButton("chevron.right", label: "Next") { page(1) }
            }
            Text(title)
                .font(.title.weight(.bold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Button("Today", action: goToToday)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .fixedSize()
                .disabled(mode == .week ? Calendar.app.isDateInToday(anchor) : range.contains(Date()))
        }
    }

    @ViewBuilder
    private var daysPicker: some View {
        if mode == .week {
            Picker("Days shown", selection: $weekDayCount) {
                Text("5 days").tag(5)
                Text("7 days").tag(7)
            }
            .pickerStyle(.segmented)
            .frame(width: 130)
        }
    }

    private var viewPicker: some View {
        Picker("View", selection: modeBinding) {
            ForEach(CalendarMode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(width: 250)
    }

    private func navButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Palette.surface))
                .overlay(Circle().strokeBorder(Palette.hairline))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.ink)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var syncStatus: some View {
        if let error = store.lastError {
            Label("Sync problem", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .help(error)
                .onTapGesture { Task { await store.load(range) } }
        } else if store.isLoading && store.lastSynced == nil {
            ProgressView()
        } else if let synced = store.lastSynced {
            Text("Updated \(synced, format: .dateTime.hour().minute())")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var title: String {
        let cal = Calendar.app
        switch mode {
        case .week:
            let days = CalendarRanges.days(in: range)
            guard let first = days.first, let last = days.last else { return "" }
            if cal.isDate(first, equalTo: last, toGranularity: .month) {
                return "\(first.formatted(.dateTime.month(.wide).day()))–\(last.formatted(.dateTime.day()))"
            }
            return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return anchor.formatted(.dateTime.month(.wide).year())
        case .schedule:
            return "Upcoming"
        }
    }
}

/// Shown until Google is connected and the family calendar is picked.
struct GoogleConnectCard: View {
    @Environment(GoogleAuth.self) private var auth
    @Environment(EventStore.self) private var store

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 44))
                    .foregroundStyle(Palette.accent)
                if !auth.isSignedIn {
                    Text("Connect your family calendar")
                        .font(.title.weight(.bold))
                    Text("Sign in with the Google account that has your shared family calendar. Events you add here show up on everyone's phones, and the other way around.")
                        .foregroundStyle(Palette.inkSecondary)
                    Button {
                        Task { await auth.signIn(); await store.loadCalendars() }
                    } label: {
                        Label("Sign in with Google", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text("Which calendar is the family calendar?")
                        .font(.title.weight(.bold))
                    CalendarPicker()
                }
                if let error = auth.lastError ?? store.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .task(id: auth.isSignedIn) {
            if auth.isSignedIn && store.calendars.isEmpty { await store.loadCalendars() }
        }
    }
}

/// List of the account's writable calendars.
struct CalendarPicker: View {
    @Environment(EventStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let writable = store.calendars.filter(\.canWrite)
        VStack(spacing: 8) {
            if writable.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
            ForEach(writable) { cal in
                Button {
                    store.selectedCalendarId = cal.id
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hexString: cal.backgroundColor) ?? Palette.family)
                            .frame(width: 16, height: 16)
                        Text(cal.displayName)
                            .font(.body.weight(.medium))
                        if cal.primary == true {
                            Text("Primary").font(.caption).foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer()
                        if store.selectedCalendarId == cal.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                        }
                    }
                    .padding(12)
                    .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension Color {
    /// "#a4bdfc" → Color
    init?(hexString: String?) {
        guard var s = hexString else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}
