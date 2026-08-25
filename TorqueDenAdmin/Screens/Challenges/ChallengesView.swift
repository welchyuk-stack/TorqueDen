import SwiftUI

struct ChallengesView: View {
    @EnvironmentObject var appState: AppState
    @State private var challenges: [AdminChallenge] = []
    @State private var loading = false
    @State private var error: String?
    @State private var selected: AdminChallenge?
    @State private var showCreate = false

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar list
            VStack(spacing: 0) {
                HStack {
                    Text("Weekly Challenges")
                        .font(.headline)
                    Spacer()
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("Create challenge")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                if loading {
                    ProgressView().padding()
                    Spacer()
                } else if let error {
                    Text(error).foregroundStyle(.red).padding().font(.caption)
                    Spacer()
                } else if challenges.isEmpty {
                    Text("No challenges").foregroundStyle(.secondary).padding()
                    Spacer()
                } else {
                    List(challenges, id: \.id, selection: $selected) { c in
                        ChallengeRowView(challenge: c)
                            .tag(c)
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(width: 240)

            Divider()

            // Detail
            if let c = selected {
                ChallengeDetailView(challenge: c, onWinnerSet: { load() })
            } else {
                ContentUnavailableView("Select a challenge", systemImage: "trophy", description: Text("Pick one from the list to review entries and pick a winner."))
            }
        }
        .onAppear { load() }
        .sheet(isPresented: $showCreate) {
            ChallengeFormView(existing: nil) { _ in load() }
        }
    }

    private func load() {
        loading = true
        error = nil
        Task {
            do {
                challenges = try await appState.api.fetchChallenges()
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}

struct ChallengeRowView: View {
    let challenge: AdminChallenge

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(challenge.emoji)
                Text(challenge.title)
                    .font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
                statusBadge
            }
            Text("#\(challenge.tag)")
                .font(.caption).foregroundStyle(.secondary)
            Text(dateRange)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var statusBadge: some View {
        Text(challenge.statusLabel)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(statusColor.opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        if challenge.isActive { return .green }
        if challenge.isUpcoming { return .blue }
        return .secondary
    }

    private var dateRange: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return "\(f.string(from: challenge.startsAt)) → \(f.string(from: challenge.endsAt))"
    }
}
