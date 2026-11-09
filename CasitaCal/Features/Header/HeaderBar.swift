import SwiftUI

/// Top bar: big clock + date, weather slot, and the member filter avatars.
struct HeaderBar: View {
    @Environment(MemberStore.self) private var members
    @Environment(DailyInfoStore.self) private var daily
    @State private var isNarrow = false

    private var showsDaily: Bool { !daily.enabledTopics.isEmpty }
    /// In portrait there's no room for both cards beside the clock and the family.
    private var usesSecondRow: Bool { showsDaily && isNarrow }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            mainRow
            if usesSecondRow {
                HStack(spacing: 16) {
                    DailyInfoChip(maxWidth: 380)
                    TonightDinnerCard()
                    Spacer(minLength: 0)
                }
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(Palette.canvas)
        .onGeometryChange(for: Bool.self) { $0.size.width < 1000 } action: { isNarrow = $0 }
    }

    private var mainRow: some View {
        HStack(alignment: .center, spacing: showsDaily ? 20 : 28) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .fixedSize()

            WeatherBadge()

            if showsDaily, !usesSecondRow {
                DailyInfoChip(maxWidth: 200)
                    .layoutPriority(1) // the dinner card gives way first
            }

            if !usesSecondRow {
                TonightDinnerCard()
            }

            Spacer()

            // Safety net: if a fresh TestFlight build hasn't arrived, say so well before it stops opening.
            if let days = AppVersion.daysUntilExpiry, days <= 14 {
                Label("Update CasitaCal in TestFlight (\(max(days, 0)) days left)", systemImage: "exclamationmark.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.orange.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 14) {
                ForEach(members.members) { member in
                    Button {
                        withAnimation(.snappy) { members.toggleVisibility(member) }
                    } label: {
                        VStack(spacing: 4) {
                            ProfileAvatar(member: member, size: 54, isActive: members.isVisible(member))
                            Text(member.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(members.isVisible(member) ? "Hide \(member.name)'s items" : "Show \(member.name)'s items")
                }
            }
            .fixedSize() // names never get squeezed; the dinner card gives way instead
        }
    }
}
