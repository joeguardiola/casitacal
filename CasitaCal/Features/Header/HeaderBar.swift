import SwiftUI

/// Top bar: big clock + date, weather slot, and the member filter avatars.
struct HeaderBar: View {
    @Environment(MemberStore.self) private var members

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
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

            // Weather lands in Milestone 4 (WeatherKit).
            Label("--°", systemImage: "cloud.sun")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.inkSecondary)
                .symbolRenderingMode(.multicolor)

            Spacer()

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
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(Palette.canvas)
    }
}
