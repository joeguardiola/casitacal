import SwiftUI

/// Top bar: big clock + date, weather, the rotating daily card, and the member filter avatars.
/// The daily card takes whatever room the family leaves, so it's wider with fewer members.
struct HeaderBar: View {
    @Environment(MemberStore.self) private var members
    @Environment(DailyInfoStore.self) private var daily
    @State private var width: CGFloat = 0

    private var showsDaily: Bool { !daily.enabledTopics.isEmpty }
    private var expiryDays: Int? { AppVersion.daysUntilExpiry.flatMap { $0 <= 14 ? $0 : nil } }
    /// The card moves to its own row when the top row can't give it room for its text:
    /// portrait, a big family, or the TestFlight warning taking space.
    private var usesSecondRow: Bool {
        showsDaily && Self.roomForCard(width: width, members: members.members.count, showsExpiry: expiryDays != nil) < 220
    }

    /// Width left for the daily card in the top row. Clock + date (longest date) and weather are
    /// about 360 pt with their spacing; each avatar is 54 pt plus 14 between; the warning ~340 pt.
    nonisolated static func roomForCard(width: CGFloat, members: Int, showsExpiry: Bool) -> CGFloat {
        let family = members > 0 ? CGFloat(members) * 68 - 14 + 16 : 0
        return width - 56 - 360 - family - (showsExpiry ? 356 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            mainRow
            if usesSecondRow {
                DailyInfoChip(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        // Always as wide as the space given, so the measurement below never depends on which row
        // the daily card is in. (Measuring the content made the card flip between rows forever.)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.canvas)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var mainRow: some View {
        HStack(alignment: .center, spacing: showsDaily ? 16 : 28) {
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
                .fixedSize() // never squeezed by the daily card

            if showsDaily, !usesSecondRow {
                DailyInfoChip(maxWidth: .infinity)
                    .layoutPriority(1) // fills the room between the weather and the family
            } else {
                Spacer()
            }

            // Safety net: if a fresh TestFlight build hasn't arrived, say so well before it stops opening.
            if let days = expiryDays {
                Label("Update CasitaCal in TestFlight (\(max(days, 0)) days left)", systemImage: "exclamationmark.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.orange.opacity(0.12), in: Capsule())
                    .fixedSize()
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
            .fixedSize() // names never get squeezed; the daily card gives way instead
        }
    }
}
