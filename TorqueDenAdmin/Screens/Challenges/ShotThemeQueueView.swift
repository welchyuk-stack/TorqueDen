import SwiftUI

struct ShotThemeQueueView: View {
    @EnvironmentObject var appState: AppState
    @State private var themes: [ShotTheme] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showAdd = false
    @State private var editing: ShotTheme?
    @State private var confirmDelete: ShotTheme?
    @State private var scheduleTheme: ShotTheme?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shot Theme Queue")
                        .font(.headline)
                    Text("Themes run Fri → Fri. Drag to reorder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showAdd = true
                } label: {
                    Label("Add Theme", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if loading && themes.isEmpty {
                ProgressView().padding(40)
                Spacer()
            } else if let error, themes.isEmpty {
                Text(error).foregroundStyle(.red).padding().font(.caption)
                Spacer()
            } else if themes.isEmpty {
                ContentUnavailableView(
                    "Queue is empty",
                    systemImage: "camera.aperture",
                    description: Text("Add themes to build up the Shot rotation.")
                )
            } else {
                List {
                    ForEach(Array(themes.enumerated()), id: \.element.id) { index, theme in
                        ShotThemeRow(
                            theme: theme,
                            position: index + 1,
                            nextFriday: nextFriday(offset: index),
                            onEdit: { editing = theme },
                            onSchedule: { scheduleTheme = theme },
                            onDelete: { confirmDelete = theme }
                        )
                    }
                    .onMove { from, to in
                        themes.move(fromOffsets: from, toOffset: to)
                        saveOrder()
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { load() }
        .sheet(isPresented: $showAdd) {
            ShotThemeFormView(existing: nil) { load() }
                .environmentObject(appState)
        }
        .sheet(item: $editing) { theme in
            ShotThemeFormView(existing: theme) { load() }
                .environmentObject(appState)
        }
        .sheet(item: $scheduleTheme) { theme in
            ScheduleShotSheet(theme: theme, onScheduled: { load() })
                .environmentObject(appState)
        }
        .confirmationDialog(
            "Delete \"\(confirmDelete?.title ?? "")\"?",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let t = confirmDelete { delete(t) }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("This removes it from the queue permanently.")
        }
    }

    private func load() {
        loading = true; error = nil
        Task {
            do {
                themes = try await appState.api.fetchShotThemes()
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    private func saveOrder() {
        let ids = themes.map(\.id)
        Task {
            try? await appState.api.reorderShotThemes(orderedIds: ids)
        }
    }

    private func delete(_ theme: ShotTheme) {
        Task {
            try? await appState.api.deleteShotTheme(id: theme.id)
            await MainActor.run { themes.removeAll { $0.id == theme.id } }
        }
    }

    /// Returns the upcoming Friday for the nth slot (0-based).
    private func nextFriday(offset: Int) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        // Find next Friday (weekday 6 in ISO8601 where Mon=2, Fri=6)
        let weekday = cal.component(.weekday, from: now) // Sun=1 ... Sat=7
        let daysUntilFri = (6 - weekday + 7) % 7  // Sun=1→5, Mon=2→4 … Fri=6→0, Sat=7→6
        let base = cal.date(byAdding: .day, value: daysUntilFri == 0 ? 7 : daysUntilFri, to: now)!
        return cal.date(byAdding: .weekOfYear, value: offset, to: base)!
    }
}

struct ShotThemeRow: View {
    let theme: ShotTheme
    let position: Int
    let nextFriday: Date
    let onEdit: () -> Void
    let onSchedule: () -> Void
    let onDelete: () -> Void

    private var fridayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        let end = Calendar.current.date(byAdding: .day, value: 7, to: nextFriday)!
        return "\(f.string(from: nextFriday)) → \(f.string(from: end))"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Position badge
            Text("\(position)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .frame(width: 24)
                .foregroundStyle(.secondary)

            Text(theme.emoji)
                .font(.title2)

            VStack(alignment: .leading, spacing: 3) {
                Text(theme.title)
                    .font(.subheadline).fontWeight(.semibold)
                Text("#\(theme.tag)")
                    .font(.caption).foregroundStyle(.secondary)
                if !theme.description.isEmpty {
                    Text(theme.description)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Projected date
            VStack(alignment: .trailing, spacing: 2) {
                Text(position == 1 ? "Up next" : "Slot \(position)")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundStyle(position == 1 ? Color.accentColor : .secondary)
                Text(fridayLabel)
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            // Actions
            HStack(spacing: 4) {
                Button {
                    onSchedule()
                } label: {
                    Image(systemName: "calendar.badge.plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .help("Schedule as a challenge now")

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("Edit theme")

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("Remove from queue")
            }
        }
        .padding(.vertical, 4)
    }
}

/// Sheet to schedule a theme as an actual challenge on the upcoming Fri→Fri window.
struct ScheduleShotSheet: View {
    let theme: ShotTheme
    let onScheduled: () -> Void

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var startsAt: Date
    @State private var endsAt: Date
    @State private var saving = false
    @State private var error: String?

    init(theme: ShotTheme, onScheduled: @escaping () -> Void) {
        self.theme = theme
        self.onScheduled = onScheduled
        let (s, e) = Self.nextFriToFri()
        _startsAt = State(initialValue: s)
        _endsAt = State(initialValue: e)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Schedule Shot")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            Form {
                Section("Theme") {
                    LabeledContent("Title") { Text("\(theme.emoji) \(theme.title)").fontWeight(.semibold) }
                    LabeledContent("Tag") { Text("#\(theme.tag)").foregroundStyle(.secondary) }
                    if !theme.description.isEmpty {
                        LabeledContent("Description") { Text(theme.description).foregroundStyle(.secondary) }
                    }
                }
                Section("Window") {
                    DatePicker("Starts (Friday)", selection: $startsAt)
                    DatePicker("Ends (Friday)", selection: $endsAt)
                }
            }
            .formStyle(.grouped)

            if let error {
                Text(error).foregroundStyle(.red).font(.caption).padding(.horizontal)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create Challenge") { schedule() }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving)
            }
            .padding()
        }
        .frame(width: 460)
    }

    private func schedule() {
        saving = true; error = nil
        Task {
            do {
                _ = try await appState.api.createChallenge(
                    title: theme.title, emoji: theme.emoji, tag: theme.tag,
                    description: theme.description, startsAt: startsAt, endsAt: endsAt
                )
                onScheduled()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }

    /// Computes the upcoming Fri 00:00 UTC → following Fri 00:00 UTC window.
    static func nextFriToFri() -> (Date, Date) {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let weekday = cal.component(.weekday, from: now) // Sun=1 … Sat=7
        let daysUntilFri = (6 - weekday + 7) % 7
        let startDay = cal.date(byAdding: .day, value: daysUntilFri == 0 ? 7 : daysUntilFri, to: now)!
        let start = cal.startOfDay(for: startDay)
        let end = cal.date(byAdding: .weekOfYear, value: 1, to: start)!
        return (start, end)
    }
}
