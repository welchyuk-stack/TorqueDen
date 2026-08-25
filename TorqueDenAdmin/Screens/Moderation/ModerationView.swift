import Combine
import SwiftUI

struct ModerationView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ModerationViewModel()
    @AppStorage("moderation.splitFraction") private var splitFraction: Double = 0.4

    var body: some View {
        HSplitView {
            reportsList
                .frame(minWidth: 280)

            detailPanel
                .frame(minWidth: 380)
        }
        .onAppear {
            if let reports = appState.adminStats?.reports {
                viewModel.updateReports(reports)
            }
        }
        .onReceive(appState.$adminStats) { stats in
            if let reports = stats?.reports {
                viewModel.updateReports(reports)
            }
        }
    }

    private var reportsList: some View {
        List(selection: $viewModel.selectedReportID) {
            if viewModel.reports.isEmpty {
                ContentUnavailableView("No open reports", systemImage: "checkmark.shield")
            } else {
                ForEach(viewModel.reports) { report in
                    ReportListRowView(report: report)
                        .tag(report.id as String?)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let id = viewModel.selectedReportID,
           let report = viewModel.reports.first(where: { $0.id == id }) {
            ReportDetailView(
                report: report,
                onAction: { action in
                    Task { await viewModel.performAction(action, reportId: report.id) }
                }
            )
        } else {
            ContentUnavailableView("Select a report", systemImage: "arrow.left")
        }
    }
}
