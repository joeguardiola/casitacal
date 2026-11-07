import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case calendar, chores, lists, meals, photos, settings

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .calendar: "calendar"
        case .chores: "checklist"
        case .lists: "list.bullet.rectangle"
        case .meals: "fork.knife"
        case .photos: "photo.on.rectangle"
        case .settings: "gearshape"
        }
    }
}

/// iPad: Skylight-style icon rail + header + content.
/// iPhone: standard tab bar (companion for chores/lists/meals).
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var section: AppSection = .calendar

    var body: some View {
        if sizeClass == .compact {
            TabView(selection: $section) {
                ForEach(AppSection.allCases) { s in
                    Tab(s.title, systemImage: s.systemImage, value: s) {
                        NavigationStack {
                            SectionContent(section: s)
                                .navigationTitle(s.title)
                        }
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
        }
    }
}

struct SectionContent: View {
    let section: AppSection

    var body: some View {
        switch section {
        case .calendar: CalendarScreen()
        case .chores: ComingSoonView(title: "Chores", systemImage: section.systemImage, milestone: "Milestone 5")
        case .lists: ComingSoonView(title: "Lists", systemImage: section.systemImage, milestone: "Milestone 5")
        case .meals: ComingSoonView(title: "Meals", systemImage: section.systemImage, milestone: "Milestone 5")
        case .photos: PhotosScreen()
        case .settings: SettingsScreen()
        }
    }
}

/// Vertical icon rail on the left edge (iPad).
struct SideRail: View {
    @Binding var selection: AppSection

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
            Spacer()
            railButton(.settings)
                .padding(.bottom, 12)
        }
        .frame(width: 96)
        .background(Palette.sidebar)
    }

    private func railButton(_ s: AppSection) -> some View {
        let selected = selection == s
        return Button {
            selection = s
        } label: {
            VStack(spacing: 4) {
                Image(systemName: s.systemImage)
                    .font(.system(size: 24, weight: .medium))
                Text(s.title)
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
        .buttonStyle(.plain)
        .accessibilityLabel(s.title)
    }
}
