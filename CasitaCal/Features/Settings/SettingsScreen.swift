import SwiftUI

struct SettingsScreen: View {
    @Environment(MemberStore.self) private var members
    @State private var editing: Member?
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(members.members) { member in
                        Button {
                            editing = member
                        } label: {
                            HStack(spacing: 14) {
                                ProfileAvatar(member: member, size: 40)
                                VStack(alignment: .leading) {
                                    Text(member.name).font(.headline)
                                    Text("\(member.role.label) · \(member.color.displayName) in Google Calendar")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        offsets.map { members.members[$0] }.forEach(members.delete)
                    }
                    .onMove(perform: members.move)

                    Button("Add family member", systemImage: "plus.circle.fill") { isAdding = true }
                        .disabled(members.availableColors(for: nil).isEmpty)
                } header: {
                    Text("Family")
                } footer: {
                    Text("Each person owns one Google Calendar event color. To tag an event from your phone, set its color in the Google Calendar app.")
                }

                Section("Google Calendar") {
                    LabeledContent("Account", value: "Not connected")
                    Text("Sign-in arrives in Milestone 2.")
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                }
            }
            .navigationTitle("Settings")
            .toolbar { EditButton() }
            .sheet(item: $editing) { member in
                MemberEditor(member: member, isNew: false)
            }
            .sheet(isPresented: $isAdding) {
                MemberEditor(
                    member: Member(name: "", emoji: "🙂", color: members.availableColors(for: nil).first ?? .graphite),
                    isNew: true
                )
            }
        }
    }
}

struct MemberEditor: View {
    @Environment(MemberStore.self) private var members
    @Environment(\.dismiss) private var dismiss
    @State var member: Member
    let isNew: Bool

    private let emojiChoices = ["🧔", "👩", "👨", "👱‍♀️", "🧒", "👧", "👦", "👶", "🐶", "🐱", "🙂", "⭐️"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ProfileAvatar(member: member, size: 96)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Name") {
                    TextField("Name", text: $member.name)
                        .textInputAutocapitalization(.words)
                    Picker("Role", selection: $member.role) {
                        ForEach(Member.Role.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Avatar") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(emojiChoices, id: \.self) { e in
                            Text(e)
                                .font(.system(size: 34))
                                .frame(width: 52, height: 52)
                                .background(Circle().fill(member.emoji == e ? member.color.soft : .clear))
                                .onTapGesture { member.emoji = e }
                        }
                    }
                }
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(members.availableColors(for: member)) { c in
                            Circle()
                                .fill(c.strong)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if member.color == c {
                                        Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { member.color = c }
                                .accessibilityLabel(c.displayName)
                        }
                    }
                } header: {
                    Text("Color")
                } footer: {
                    Text("Matches Google Calendar's “\(member.color.displayName)” event color.")
                }
            }
            .navigationTitle(isNew ? "New member" : member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        member.name = member.name.trimmingCharacters(in: .whitespaces)
                        members.upsert(member)
                        dismiss()
                    }
                    .disabled(member.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
