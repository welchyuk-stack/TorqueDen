import SwiftUI

struct ReportListRowView: View {
    let report: Report

    var body: some View {
        HStack(spacing: 12) {
            ContentTypeBadge(type: report.targetType)

            VStack(alignment: .leading, spacing: 2) {
                Text(report.reason)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let preview = report.contentPreview {
                    Text(preview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text("@\(report.reporterUsername)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(report.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if report.strikeCount > 0 {
                        Text("\u{25CF} \(report.strikeCount) strike\(report.strikeCount == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
