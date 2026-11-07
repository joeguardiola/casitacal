import SwiftUI

struct CalendarScreen: View {
    @Environment(GoogleAuth.self) private var auth
    @Environment(EventStore.self) private var store
    @Environment(MemberStore.self) private var memberStore
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("calendar.mode") private var mode: CalendarMode = .week
    @AppStorage("calendar.dayByPerson") private var dayByPerson = true
    // Observed so the views redraw when the week-start setting changes.
    @AppStorage(Calendar.weekStartsOnMondayKey) private var weekStartsOnMonday = true
    @State private var anchor = Date()
    @State private var selected: CalendarEvent?
    @State private var isAdding = false

    private var range: DateInterval { CalendarRanges.range(for: mode, anchor: anchor) }

    private var visibleEvents: [CalendarEvent] {
        store.events.filter {
            EventMapper.isVisible($0, members: memberStore.members, hidden: memberStore.hiddenMemberIDs)
        }
    }

    private var visibleMembers: [Member] {
        memberStore.members.filter(memberStore.isVisible)
    }

    var body: some View {
        VStack(spacing: 16) {
            toolbar
            content
        }
        .padding(24)
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
        if mode == .day { return anchor }
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
        if auth.state == .signedOut || store.selectedCalendarId == nil {
            GoogleConnectCard()
                .frame(maxWidth: 560)
                .frame(maxHeight: .infinity)
        } else {
            switch mode {
            case .day:
                DayView(day: anchor, events: visibleEvents, members: visibleMembers, byPerson: $dayByPerson) { selected = $0 }
            case .week:
                WeekView(days: CalendarRanges.days(in: range), events: visibleEvents, members: memberStore.members,
                         onSelect: { selected = $0 }, onOpenDay: openDay)
            case .month:
                MonthView(anchor: anchor, days: CalendarRanges.monthGrid(for: anchor), events: visibleEvents,
                          members: memberStore.members, onOpenDay: openDay)
            case .schedule:
                ScheduleView(days: CalendarRanges.days(in: range), events: visibleEvents, members: memberStore.members) { selected = $0 }
            }
        }
    }

    private func openDay(_ day: Date) {
        withAnimation(.snappy) {
            anchor = day
            mode = .day
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                navButton("chevron.left", label: "Previous") { anchor = CalendarRanges.step(anchor, mode: mode, by: -1) }
                navButton("chevron.right", label: "Next") { anchor = CalendarRanges.step(anchor, mode: mode, by: 1) }
            }
            Text(title)
                .font(.title.weight(.bold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Button("Today") { withAnimation(.snappy) { anchor = Date() } }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(mode == .day ? Calendar.app.isDateInToday(anchor) : range.contains(Date()))

            Spacer()

            syncStatus

            if mode == .day {
                Toggle(isOn: $dayByPerson) {
                    Label("By person", systemImage: "person.2")
                }
                .toggleStyle(.button)
                .controlSize(.large)
            }

            Picker("View", selection: $mode.animation(.snappy)) {
                ForEach(CalendarMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 360)
        }
    }

    private func navButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy, action) }) {
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
        }
    }

    private var title: String {
        let cal = Calendar.app
        switch mode {
        case .day:
            return anchor.formatted(.dateTime.weekday(.wide).month(.wide).day())
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
