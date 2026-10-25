import SwiftUI

struct ReportDetailView: View {
    let report: Report
    let onAction: (ModerationAction) async -> Void

    @State private var showConfirmation = false
    @State private var pendingAction: ModerationAction?
    @State private var isProcessing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("Reported Content") {
                ScrollView {
                    Text(report.contentPreview ?? "User profile reported directly")
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }

            GroupBox("Reported User") {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.ember)
                        .frame(width: 32, height: 32)
                        .overlay {
                            Text(report.reporterUsername.prefix(1).uppercased())
                                .foregroundColor(.white)
                                .fontWeight(.bold)
                        }
                    VStack(alignment: .leading) {
                        Text("@\(report.reporterUsername)")
                            .fontWeight(.semibold)
                        if report.strikeCount > 0 {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text("\(report.strikeCount) strike\(report.strikeCount == 1 ? "" : "s")")
                                    .foregroundColor(.orange)
                            }
                            .font(.caption)
                        } else {
                            Label("No strikes", systemImage: "checkmark")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Details") {
                VStack(alignment: .leading, spacing: 8) {
                    detailRow("Reason", report.reason)
                    if let note = report.note {
                        detailRow("Note", note)
                    }
                    detailRow("Target Type", report.targetType)
                    detailRow("Reported", report.createdAt.formatted(date: .long, time: .shortened))
                }
                .padding(.vertical, 4)
            }

            Spacer()
        }
        .padding()
        .toolbar {
            ToolbarItemGroup {
                Button("No Action") { pendingAction = .noAction; showConfirmation = true }
                    .disabled(isProcessing)
                Button("Warn User") { pendingAction = .warn; showConfirmation = true }
                    .disabled(isProcessing)
                Button("Delete Content") { pendingAction = .delete; showConfirmation = true }
                    .disabled(isProcessing)
                Button("Delete + Ban") { pendingAction = .deleteAndBan; showConfirmation = true }
                    .disabled(isProcessing)
            }
        }
        .confirmationDialog(
            pendingAction?.confirmationMessage ?? "",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Proceed", role: pendingAction == .noAction ? nil : .destructive) {
                if let action = pendingAction {
                    isProcessing = true
                    Task {
                        await onAction(action)
                        isProcessing = false
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
            Spacer()
        }
    }
}
