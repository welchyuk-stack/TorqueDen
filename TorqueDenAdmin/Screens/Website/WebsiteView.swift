import SwiftUI
import Charts

struct WebsiteView: View {
    @StateObject private var viewModel = WebsiteViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerRow

                if viewModel.isLoading && viewModel.stats == nil {
                    ProgressView("Loading\u{2026}")
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let error = viewModel.error, viewModel.stats == nil {
                    if !viewModel.hasCredentials {
                        setupPrompt
                    } else {
                        ContentUnavailableView(
                            "Could Not Load",
                            systemImage: "exclamationmark.triangle",
                            description: Text(error)
                        )
                    }
                } else if let stats = viewModel.stats {
                    summaryTiles(stats)
                    Divider()
                    requestsChart(stats)
                    Divider()
                    countriesTable(stats)
                } else {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "globe",
                        description: Text("Tap Refresh to load website stats.")
                    )
                }
            }
            .padding(24)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Picker("Period", selection: $viewModel.selectedDays) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .onChange(of: viewModel.selectedDays) { _, _ in
                        Task { await viewModel.load() }
                    }

                    Button { Task { await viewModel.load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack {
            Image(systemName: "globe")
                .font(.title)
                .foregroundColor(.ember)
            Text("Website")
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer()
            Text("torquedenapp.com")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var setupPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Add Cloudflare credentials in Settings to enable website analytics.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Text("You'll need a Cloudflare API token with Zone Analytics:Read permission, and your Zone ID.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func summaryTiles(_ stats: CloudflareStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUMMARY — LAST \(viewModel.selectedDays) DAYS")
                .font(.caption)
                .foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                StatTileView(label: "Requests", value: formatted(stats.requests))
                StatTileView(label: "Page Views", value: formatted(stats.pageViews))
                StatTileView(label: "Bandwidth", value: ByteFormatter.string(fromBytes: stats.bytes))
                StatTileView(
                    label: "Pages / Request",
                    value: stats.requests > 0
                        ? String(format: "%.2f", Double(stats.pageViews) / Double(stats.requests))
                        : "—"
                )
            }
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                Text("Session duration and unique visitor counts are not available on Cloudflare's free plan.")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private func requestsChart(_ stats: CloudflareStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DAILY REQUESTS")
                .font(.caption)
                .foregroundColor(.secondary)

            if stats.dailyStats.isEmpty {
                Text("No daily data available for this period.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Chart(stats.dailyStats) { day in
                    BarMark(
                        x: .value("Date", day.parsedDate, unit: .day),
                        y: .value("Requests", day.requests)
                    )
                    .foregroundStyle(Color.ember.gradient)
                }
                .frame(height: 140)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, stats.dailyStats.count / 7))) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
            }
        }
    }

    private func countriesTable(_ stats: CloudflareStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOP COUNTRIES")
                .font(.caption)
                .foregroundColor(.secondary)

            if stats.countries.isEmpty {
                Text("No country data available for this period.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                let maxRequests = stats.countries.first?.requests ?? 1
                VStack(spacing: 6) {
                    ForEach(stats.countries.prefix(15)) { country in
                        HStack(spacing: 10) {
                            Text(country.flagEmoji)
                                .font(.title3)
                                .frame(width: 28)
                            Text(country.displayName)
                                .frame(width: 160, alignment: .leading)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.ember.opacity(0.7))
                                    .frame(width: geo.size.width * CGFloat(country.requests) / CGFloat(maxRequests))
                            }
                            .frame(height: 14)
                            Text(formatted(country.requests))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private func formatted(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
