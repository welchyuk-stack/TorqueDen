import SwiftUI

struct UsersView: View {
    @StateObject private var viewModel = UsersViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "person.3.fill")
                    .font(.title2)
                    .foregroundColor(.ember)
                Text("Users")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                Button { Task { await viewModel.load() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider()

            if viewModel.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error, viewModel.users.isEmpty {
                ContentUnavailableView("Could Not Load", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                List {
                    Section {
                        ForEach(viewModel.users) { user in
                            UserRow(user: user)
                        }
                        if viewModel.hasMore {
                            HStack {
                                Spacer()
                                if viewModel.isLoadingMore {
                                    ProgressView()
                                } else {
                                    Button("Load more") { Task { await viewModel.loadMore() } }
                                        .buttonStyle(.borderless)
                                }
                                Spacer()
                            }
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        HStack {
                            Text("USERNAME").frame(minWidth: 140, alignment: .leading)
                            Text("JOINED").frame(minWidth: 120, alignment: .leading)
                            Text("LAST SEEN").frame(minWidth: 160, alignment: .leading)
                            Text("STATUS").frame(minWidth: 80, alignment: .leading)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .task { await viewModel.load() }
    }
}

private struct UserRow: View {
    let user: AdminUser

    private var onlineStatus: (label: String, color: Color) {
        guard let lastSeen = user.lastSignInAt else { return ("Never", .secondary) }
        let ago = Date().timeIntervalSince(lastSeen)
        if ago < 300        { return ("Online", .green) }
        if ago < 3600       { return ("Recently", .green.opacity(0.7)) }
        if ago < 86400      { return ("Today", .secondary) }
        if ago < 86400 * 7  { return ("This week", .secondary) }
        return ("Inactive", .secondary.opacity(0.6))
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(user.username.map { "@\($0)" } ?? "—")
                .font(.body)
                .frame(minWidth: 140, alignment: .leading)

            Text(user.createdAt, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(minWidth: 120, alignment: .leading)

            Group {
                if let lastSeen = user.lastSignInAt {
                    Text(lastSeen, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 160, alignment: .leading)

            HStack(spacing: 4) {
                Circle()
                    .fill(onlineStatus.color)
                    .frame(width: 7, height: 7)
                Text(onlineStatus.label)
                    .font(.caption)
                    .foregroundColor(onlineStatus.color)
            }
            .frame(minWidth: 80, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}
