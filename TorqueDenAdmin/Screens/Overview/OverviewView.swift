import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = OverviewViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerView

                if appState.isLoading && appState.adminStats == nil {
                    ProgressView("Loading\u{2026}")
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let error = appState.lastError, appState.adminStats == nil {
                    ContentUnavailableView(
                        "Could Not Load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error.localizedDescription)
                    )
                } else if let stats = appState.adminStats {
                    statTilesSection(stats: stats)
                    Divider()
                    subscriberFooter
                    Divider()
                    usageSection(stats: stats)
                } else {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "chart.bar",
                        description: Text("Tap Refresh to load stats.")
                    )
                }
            }
            .padding(24)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Text("Updated \(viewModel.relativeTimestamp(from: appState.adminStats?.generatedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button { Task { await appState.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(appState.isLoading)
                }
            }
        }
    }

    private var headerView: some View {
        HStack {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.title)
                .foregroundColor(.ember)
            Text("TorqueDen Admin")
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer()
        }
    }

    private func statTilesSection(stats: AdminStatsResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            tileGroup("Users", tiles: [
                ("Total Users", "\(stats.users.total)"),
                ("New (7d)", "\(stats.users.new7D)"),
                ("New (30d)", "\(stats.users.new30D)"),
            ])
            tileGroup("Clubs", tiles: [
                ("Total Clubs", "\(stats.clubs.total)"),
                ("Public", "\(stats.clubs.public)"),
                ("Private", "\(stats.clubs.private)"),
            ])
            tileGroup("Content & Engagement", tiles: [
                ("Cars", "\(stats.content.cars)"),
                ("Build Posts", "\(stats.content.posts)"),
                ("Comments", "\(stats.content.comments)"),
                ("Reactions", "\(stats.content.reactions)"),
            ])
            tileGroup("Revenue (Subscribers)", tiles: [
                ("Premium", "\(stats.subscribers.premium)"),
                ("Partner", "\(stats.subscribers.partner)"),
            ])
        }
    }

    private func tileGroup(_ title: String, tiles: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                ForEach(tiles, id: \.0) { label, value in
                    StatTileView(label: label, value: value)
                }
            }
        }
    }

    private var subscriberFooter: some View {
        Text("Subscriber counts only. Revenue figures live in AdMob.")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private func usageSection(stats: AdminStatsResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supabase Usage (Free Tier)")
                .font(.headline)

            if let usage = stats.usage {
                UsageRowView(
                    label: "Database size",
                    currentBytes: usage.dbSizeBytes,
                    limitBytes: usage.limits.dbSizeBytes
                )
                UsageRowView(
                    label: "Storage",
                    currentBytes: usage.storageSizeBytes,
                    limitBytes: usage.limits.storageSizeBytes
                )
            } else {
                Label("Usage data unavailable.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
