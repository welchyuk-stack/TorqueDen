import SwiftUI

struct ChallengeDetailView: View {
    let challenge: AdminChallenge
    let onWinnerSet: () -> Void

    @EnvironmentObject var appState: AppState
    @State private var entries: [AdminEntry] = []
    @State private var loading = false
    @State private var error: String?
    @State private var winnerId: String?
    @State private var saving = false
    @State private var showEdit = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(challenge.emoji).font(.largeTitle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(challenge.title).font(.title2).fontWeight(.bold)
                            Text("#\(challenge.tag)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !challenge.description.isEmpty {
                        Text(challenge.description)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 12) {
                        Label(dateRange, systemImage: "calendar")
                            .font(.caption).foregroundStyle(.secondary)
                        statusBadge
                        if challenge.winnerEntryId != nil {
                            Label("Winner set", systemImage: "trophy.fill")
                                .font(.caption).foregroundStyle(.yellow)
                        }
                    }
                }
                Spacer()
                HStack {
                    Button("Edit") { showEdit = true }
                    Button("Delete", role: .destructive) { confirmDelete = true }
                        .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            if loading {
                ProgressView("Loading entries…").padding()
                Spacer()
            } else if let error {
                Text(error).foregroundStyle(.red).padding()
                Spacer()
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "No entries yet",
                    systemImage: "photo.on.rectangle",
                    description: Text("Posts tagged #\(challenge.tag) during the challenge window will appear here.")
                )
            } else {
                // Winner picker banner (only for ended/active challenges without winner)
                if challenge.winnerEntryId == nil && !challenge.isUpcoming {
                    HStack {
                        Image(systemName: "trophy").foregroundStyle(.yellow)
                        Text(winnerId == nil ? "Select an entry below to pick as winner" : "Winner selected — tap Save to confirm")
                            .font(.subheadline)
                        Spacer()
                        if let w = winnerId {
                            Button("Save Winner") { saveWinner(entryId: w) }
                                .buttonStyle(.borderedProminent)
                                .disabled(saving)
                            Button("Clear") { winnerId = nil }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 10)
                    .background(Color.yellow.opacity(0.08))

                    Divider()
                }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(entries) { entry in
                            EntryTileView(
                                entry: entry,
                                isWinner: entry.id == (challenge.winnerEntryId ?? winnerId),
                                isSelectable: challenge.winnerEntryId == nil && !challenge.isUpcoming,
                                onSelect: { winnerId = entry.id }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear { loadEntries() }
        .onChange(of: challenge.id) { _, _ in loadEntries() }
        .sheet(isPresented: $showEdit) {
            ChallengeFormView(existing: challenge) { _ in onWinnerSet() }
        }
        .confirmationDialog("Delete \(challenge.title)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { deleteChallenge() }
        } message: {
            Text("This will permanently delete the challenge and all associated badges.")
        }
    }

    private func loadEntries() {
        loading = true; error = nil
        Task {
            do {
                entries = try await appState.api.fetchChallengeEntries(
                    tag: challenge.tag,
                    startsAt: challenge.startsAt,
                    endsAt: challenge.endsAt
                )
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    private func saveWinner(entryId: String) {
        let entry = entries.first(where: { $0.id == entryId })
        saving = true
        Task {
            do {
                try await appState.api.setChallengeWinner(
                    challengeId: challenge.id,
                    entryId: entryId,
                    carId: entry?.car?.id
                )
                onWinnerSet()
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }

    private func deleteChallenge() {
        Task {
            try? await appState.api.deleteChallenge(id: challenge.id)
            onWinnerSet()
        }
    }

    private var dateRange: String {
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"
        return "\(f.string(from: challenge.startsAt)) – \(f.string(from: challenge.endsAt))"
    }

    private var statusBadge: some View {
        let color: Color = challenge.isActive ? .green : challenge.isUpcoming ? .blue : .secondary
        return Text(challenge.statusLabel)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct EntryTileView: View {
    let entry: AdminEntry
    let isWinner: Bool
    let isSelectable: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                if let url = entry.firstImageUrl, let imgUrl = URL(string: url) {
                    AsyncImage(url: imgUrl) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Color.secondary.opacity(0.2))
                    }
                    .frame(height: 160)
                    .clipped()
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                        .frame(height: 160)
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }

                if isWinner {
                    Text("🏆 Winner")
                        .font(.caption).fontWeight(.bold)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.yellow.opacity(0.9), in: Capsule())
                        .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.car?.title ?? "Unknown car")
                    .font(.subheadline).fontWeight(.semibold).lineLimit(1)
                Text(entry.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack {
                    Label("\(entry.likeCount)", systemImage: "heart")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.createdAt, style: .date)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(10)

            if isSelectable {
                Button(isWinner ? "Selected as Winner" : "Pick as Winner") { onSelect() }
                    .buttonStyle(.borderedProminent)
                    .tint(isWinner ? .yellow : .accentColor)
                    .frame(maxWidth: .infinity)
                    .padding([.horizontal, .bottom], 10)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isWinner ? Color.yellow : Color.secondary.opacity(0.2), lineWidth: isWinner ? 2 : 0.5)
        )
    }
}
