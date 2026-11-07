import SwiftUI

enum CalendarMode: String, CaseIterable, Identifiable {
    case day, week, month, schedule
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Calendar shell. Real Google-backed views arrive in Milestone 2;
/// for now this shows the week frame so the layout can be judged on the iPad.
struct CalendarScreen: View {
    @State private var mode: CalendarMode = .week
    @State private var anchor = Date()

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Picker("View", selection: $mode) {
                    ForEach(CalendarMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Spacer()

                Button("Today") { anchor = Date() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            WeekFrame(anchor: anchor)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas)
        .overlay(alignment: .bottomTrailing) {
            Button {
                // Add sheet arrives in Milestone 3.
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(Palette.accent))
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            }
            .padding(28)
            .accessibilityLabel("Add")
        }
    }
}

/// Seven day columns with headers, today highlighted.
struct WeekFrame: View {
    let anchor: Date
    private let calendar = Calendar.current

    private var days: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(days, id: \.self) { day in
                let isToday = calendar.isDateInToday(day)
                VStack(spacing: 10) {
                    VStack(spacing: 2) {
                        Text(day, format: .dateTime.weekday(.abbreviated))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isToday ? Palette.accent : Palette.inkSecondary)
                        Text(day, format: .dateTime.day())
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(isToday ? .white : Palette.ink)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(isToday ? Palette.accent : .clear))
                    }
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Palette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(isToday ? Palette.accent.opacity(0.5) : Palette.hairline, lineWidth: isToday ? 2 : 1)
                        )
                }
            }
        }
    }
}
