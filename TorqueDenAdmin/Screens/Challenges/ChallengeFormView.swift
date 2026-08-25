import SwiftUI

struct ChallengeFormView: View {
    let existing: AdminChallenge?
    let onSaved: (AdminChallenge?) -> Void

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var emoji: String
    @State private var tag: String
    @State private var description: String
    @State private var startsAt: Date
    @State private var endsAt: Date
    @State private var saving = false
    @State private var error: String?

    init(existing: AdminChallenge?, onSaved: @escaping (AdminChallenge?) -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        let now = Date()
        _title = State(initialValue: existing?.title ?? "")
        _emoji = State(initialValue: existing?.emoji ?? "🏁")
        _tag = State(initialValue: existing?.tag ?? "")
        _description = State(initialValue: existing?.description ?? "")
        _startsAt = State(initialValue: existing?.startsAt ?? now)
        _endsAt = State(initialValue: existing?.endsAt ?? now.addingTimeInterval(7 * 86400))
    }

    var isEditing: Bool { existing != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(isEditing ? "Edit Challenge" : "New Challenge")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            Form {
                Section("Details") {
                    HStack {
                        TextField("Emoji", text: $emoji).frame(width: 60)
                        TextField("Title", text: $title).textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("#")
                        TextField("tag (no spaces, lowercase)", text: $tag)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: tag) { _, v in
                                tag = v.lowercased().replacingOccurrences(of: " ", with: "")
                            }
                    }
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...5)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Window") {
                    DatePicker("Starts", selection: $startsAt)
                    DatePicker("Ends", selection: $endsAt)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 300)

            if let error {
                Text(error).foregroundStyle(.red).font(.caption).padding(.horizontal)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isEditing ? "Save Changes" : "Create Challenge") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.isEmpty || tag.isEmpty || saving)
            }
            .padding()
        }
        .frame(width: 480)
    }

    private func save() {
        saving = true; error = nil
        Task {
            do {
                if let existing {
                    try await appState.api.updateChallenge(
                        id: existing.id, title: title, emoji: emoji,
                        tag: tag, description: description,
                        startsAt: startsAt, endsAt: endsAt
                    )
                    onSaved(nil)
                } else {
                    let c = try await appState.api.createChallenge(
                        title: title, emoji: emoji, tag: tag,
                        description: description, startsAt: startsAt, endsAt: endsAt
                    )
                    onSaved(c)
                }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}
