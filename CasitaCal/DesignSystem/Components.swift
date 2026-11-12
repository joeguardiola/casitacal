import SwiftUI

/// Round profile avatar with a colored ring.
struct ProfileAvatar: View {
    let member: Member
    var size: CGFloat = 52
    var isActive: Bool = true

    var body: some View {
        ZStack {
            Circle().fill(member.color.soft)
            Text(member.emoji.isEmpty ? member.initial : member.emoji)
                .font(.system(size: size * 0.48))
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(member.color.strong, lineWidth: size * 0.07))
        .opacity(isActive ? 1 : 0.35)
        .saturation(isActive ? 1 : 0)
        .accessibilityLabel(member.name)
    }
}

/// Rounded surface card used throughout the dashboard.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
    }
}

/// Placeholder for features that land in later milestones.
struct ComingSoonView: View {
    let title: String
    let systemImage: String
    let milestone: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text("Coming in \(milestone).")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
    }
}
