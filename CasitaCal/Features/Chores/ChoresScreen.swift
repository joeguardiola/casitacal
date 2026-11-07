import SwiftUI

/// Skylight-style chore chart: a column per person with big tap-to-complete cards.
struct ChoresScreen: View {
    @Environment(ChoreStore.self) private var store
    @Environment(MemberStore.self) private var memberStore
    @State private var day = Date()
    @State private var editing: Chore?
    @State private var isAdding = false

    private var columns: [Member?] {
        var cols: [Member?] = memberStore.members.filter(memberStore.isVisible)
        if store.hasAnyoneChores(on: day) { cols.append(nil) }
        return cols
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            if store.chores.isEmpty {
                ContentUnavailableView {
                    Label("No chores yet", systemImage: "checklist")
                } description: {
                    Text("Add chores like “Make bed”, “Feed the dog” or “Empty dishwasher”, pick who does them and how often. Kids earn ⭐️ for each one.")
                } actions: {
                    Button("Add a chore") { isAdding = true }.buttonStyle(.borderedProminent).controlSize(.large)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(columns, id: \.?.id) { member in
                            ChoreColumn(member: member, day: day, onEdit: { editing = $0 })
                                .frame(width: columnWidth)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas)
        .overlay(alignment: .bottomTrailing) { AddButton(label: "Add chore") { isAdding = true } }
        .sheet(isPresented: $isAdding) { ChoreEditor(chore: nil, defaultDay: day) }
        .sheet(item: $editing) { ChoreEditor(chore: $0, defaultDay: day) }
    }

    private var columnWidth: CGFloat {
        columns.count <= 4 ? 280 : 250
    }

    private var header: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                CircleNavButton(symbol: "chevron.left", label: "Previous day") { shift(-1) }
                CircleNavButton(symbol: "chevron.right", label: "Next day") { shift(1) }
            }
            Text(Calendar.app.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.title.weight(.bold))
            if !Calendar.app.isDateInToday(day) {
                Button("Today") { withAnimation(.snappy) { day = Date() } }
                    .buttonStyle(.bordered).controlSize(.large)
            }
            Spacer()
        }
    }

    private func shift(_ n: Int) {
        withAnimation(.snappy) { day = Calendar.app.date(byAdding: .day, value: n, to: day) ?? day }
    }
}

private struct ChoreColumn: View {
    let member: Member?
    let day: Date
    var onEdit: (Chore) -> Void

    @Environment(ChoreStore.self) private var store

    var body: some View {
        let chores = store.chores(for: member?.id, on: day)
        let done = chores.filter { store.isDone($0, member: member?.id, on: day) }.count
        let color = member?.color.strong ?? Palette.family

        VStack(spacing: 12) {
            // Header: avatar, name, progress, stars this week
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(color.opacity(0.18), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: chores.isEmpty ? 0 : CGFloat(done) / CGFloat(chores.count))
                        .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.5), value: done)
                    if let member {
                        ProfileAvatar(member: member, size: 62)
                    } else {
                        Image(systemName: "person.3.fill").font(.title2).foregroundStyle(color)
                            .frame(width: 62, height: 62)
                    }
                }
                .frame(width: 78, height: 78)
                Text(member?.name ?? "Anyone").font(.title3.weight(.bold))
                HStack(spacing: 10) {
                    Text("\(done)/\(chores.count) done").foregroundStyle(Palette.inkSecondary)
                    if let member {
                        Label("\(store.weeklyStars(for: member.id, weekOf: day))", systemImage: "star.fill")
                            .foregroundStyle(.orange)
                            .help("Stars this week")
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.top, 6)

            ScrollView {
                VStack(spacing: 10) {
                    if !chores.isEmpty && done == chores.count {
                        Text("All done! 🎉")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(color)
                            .padding(.vertical, 6)
                            .transition(.scale.combined(with: .opacity))
                    }
                    ForEach(chores) { chore in
                        ChoreCard(chore: chore, color: color, isDone: store.isDone(chore, member: member?.id, on: day)) {
                            withAnimation(.spring(duration: 0.35)) { store.toggle(chore, member: member?.id, on: day) }
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { onEdit(chore) }
                            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(chore) }
                        }
                    }
                    if chores.isEmpty {
                        Text("Nothing today")
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.vertical, 20)
                    }
                }
                .padding(10)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.hairline))
    }
}

private struct ChoreCard: View {
    let chore: Chore
    let color: Color
    let isDone: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(chore.emoji)
                    .font(.system(size: 34))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(isDone ? Color.white.opacity(0.35) : color.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(chore.title)
                        .font(.headline)
                        .strikethrough(isDone)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if chore.timeOfDay != .anytime {
                            Label(chore.timeOfDay.label, systemImage: chore.timeOfDay.symbol)
                        }
                        if chore.stars > 0 {
                            Text(String(repeating: "★", count: min(chore.stars, 5)))
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .opacity(0.75)
                }
                Spacer(minLength: 0)
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 30))
                    .foregroundStyle(isDone ? .white : color.opacity(0.6))
            }
            .padding(12)
            .foregroundStyle(isDone ? .white : Palette.ink)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(isDone ? color : color.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chore.title)\(isDone ? ", done" : "")")
        .accessibilityHint(isDone ? "Mark not done" : "Mark done")
    }
}

/// Big orange floating "+" (shared by Calendar-like screens).
struct AddButton: View {
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(Circle().fill(Palette.accent))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
        .padding(28)
        .accessibilityLabel(label)
    }
}

struct CircleNavButton: View {
    let symbol: String
    let label: String
    var action: () -> Void

    var body: some View {
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
}
