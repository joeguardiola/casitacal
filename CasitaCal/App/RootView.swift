import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case calendar, chores, lists, meals, settings

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .calendar: "calendar"
        case .chores: "checklist"
        case .lists: "list.bullet.rectangle"
        case .meals: "fork.knife"
        case .settings: "gearshape"
        }
    }
}

/// iPad: Skylight-style icon rail + header + content.
/// iPhone: standard tab bar (companion for chores/lists/meals).
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    // `-startSection chores` (launch argument) opens a tab directly — handy for screenshots.
    @State private var section: AppSection = UserDefaults.standard.string(forKey: "startSection").flatMap(AppSection.init) ?? .calendar
    @Environment(KioskController.self) private var kiosk

    var body: some View {
        if sizeClass == .compact {
            // Phone: companion tabs (no photo frame on a phone).
            TabView(selection: $section) {
                ForEach(AppSection.allCases) { s in
                    Tab(s.title, systemImage: s.systemImage, value: s) {
                        SectionContent(section: s)
                    }
                }
            }
        } else {
            HStack(spacing: 0) {
                SideRail(selection: $section)
                VStack(spacing: 0) {
                    HeaderBar()
                    Divider().overlay(Palette.hairline)
                    SectionContent(section: section)
                }
            }
            .background(Palette.canvas)
            .overlay { KioskOverlay() }
            // The header already shows the time; give the display the whole screen.
            .statusBarHidden(true)
            // Waking from the slideshow or night clock always lands on the calendar.
            .onChange(of: kiosk.wakeCount) { section = .calendar }
        }
    }
}

struct SectionContent: View {
    let section: AppSection
    @Environment(Persistence.self) private var persistence

    var body: some View {
        // Household screens wait for the household to arrive on phones (iCloud).
        if [.chores, .meals].contains(section) && !persistence.hasHousehold {
            WaitingForHouseholdView()
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .calendar: CalendarScreen()
        case .chores: ChoresScreen()
        case .lists: ListsScreen()
        case .meals: MealsScreen()
        case .settings: SettingsScreen()
        }
    }
}

/// Vertical icon rail on the left edge (iPad).
struct SideRail: View {
    @Binding var selection: AppSection
    @Environment(KioskController.self) private var kiosk
    @Environment(PhotoLibrary.self) private var photos
    @State private var settingUpPhotos = false

    var body: some View {
        VStack(spacing: 10) {
            Image("Logo")
                .resizable()
                .interpolation(.high)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                .padding(.vertical, 16)
                .accessibilityLabel("CasitaCal")
            ForEach(AppSection.allCases.filter { $0 != .settings }) { s in
                railButton(s)
            }
            slideshowButton
            Spacer()
            railButton(.settings)
                .padding(.bottom, 12)
        }
        .frame(width: 96)
        .background(Palette.sidebar)
        .sheet(isPresented: $settingUpPhotos) { PhotosScreen() }
    }

    /// Not a section: it starts the slideshow on top of whatever is showing.
    private var slideshowButton: some View {
        Button {
            if photos.canRead && photos.selectedAlbumId != nil {
                kiosk.startSlideshowNow()
            } else {
                settingUpPhotos = true
            }
        } label: {
            railLabel("Slideshow", systemImage: "photo.on.rectangle", selected: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start slideshow")
    }

    private func railButton(_ s: AppSection) -> some View {
        Button {
            selection = s
        } label: {
            railLabel(s.title, systemImage: s.systemImage, selected: selection == s)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.title)
    }

    private func railLabel(_ title: String, systemImage: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .frame(width: 76, height: 68)
        .foregroundStyle(selected ? Color.white : Palette.inkSecondary)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(selected ? Palette.accent : .clear)
        )
        .contentShape(Rectangle())
    }
}
