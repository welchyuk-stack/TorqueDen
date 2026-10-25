import SwiftUI

struct ShotThemeFormView: View {
    let existing: ShotTheme?
    let onSaved: () -> Void

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var emoji: String
    @State private var tag: String
    @State private var description: String
    @State private var saving = false
    @State private var error: String?

    init(existing: ShotTheme?, onSaved: @escaping () -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        _title = State(initialValue: existing?.title ?? "")
        _emoji = State(initialValue: existing?.emoji ?? "📸")
        _tag = State(initialValue: existing?.tag ?? "")
        _description = State(initialValue: existing?.description ?? "")
    }

    var isEditing: Bool { existing != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "Edit Theme" : "New Shot Theme")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            Form {
                Section("Theme") {
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
                    TextField("Description (shown to users)", text: $description, axis: .vertical)
                        .lineLimit(3...5)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 220)

            if let error {
                Text(error).foregroundStyle(.red).font(.caption).padding(.horizontal)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isEditing ? "Save" : "Add to Queue") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.isEmpty || tag.isEmpty || saving)
            }
            .padding()
        }
        .frame(width: 440)
    }

    private func save() {
        saving = true; error = nil
        Task {
            do {
                if let existing {
                    try await appState.api.updateShotTheme(
                        id: existing.id, title: title, emoji: emoji,
                        tag: tag, description: description
                    )
                } else {
                    _ = try await appState.api.createShotTheme(
                        title: title, emoji: emoji, tag: tag, description: description
                    )
                }
                onSaved()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}
