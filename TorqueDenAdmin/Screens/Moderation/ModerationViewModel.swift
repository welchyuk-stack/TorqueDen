import Foundation
import SwiftUI

@MainActor
class ModerationViewModel: ObservableObject {
    @Published var reports: [Report] = []
    @Published var selectedReportID: String?
    @Published var isProcessing = false
    @Published var errorMessage: String?

    private let client = AdminAPIClient()

    func updateReports(_ newReports: [Report]) {
        let selectedID = selectedReportID
        reports = newReports
        if let selectedID, !reports.contains(where: { $0.id == selectedID }) {
            selectedReportID = reports.first?.id
        } else {
            selectedReportID = selectedID ?? reports.first?.id
        }
    }

    func performAction(_ action: ModerationAction, reportId: String) async {
        isProcessing = true
        errorMessage = nil
        do {
            switch action {
            case .noAction:
                _ = try await client.resolveReport(id: reportId, status: .dismissed)
            case .warn:
                _ = try await client.warnUser(reportId: reportId)
            case .delete:
                _ = try await client.deleteContent(reportId: reportId)
            case .deleteAndBan:
                _ = try await client.deleteAndBan(reportId: reportId)
            }
            if let idx = reports.firstIndex(where: { $0.id == reportId }) {
                reports.remove(at: idx)
                selectedReportID = reports.first?.id
            }
        } catch {
            errorMessage = "Action failed. Try again."
        }
        isProcessing = false
    }
}

enum ModerationAction: String, CaseIterable {
    case noAction = "No Action"
    case warn = "Warn User"
    case delete = "Delete Content"
    case deleteAndBan = "Delete + Ban"

    var shortcut: KeyboardShortcut? {
        switch self {
        case .noAction: return .init("d", modifiers: EventModifiers.command)
        case .warn: return .init("w", modifiers: EventModifiers.command)
        case .delete: return .init(.delete, modifiers: EventModifiers.command)
        case .deleteAndBan: return .init("b", modifiers: [EventModifiers.command, EventModifiers.shift])
        }
    }

    var confirmationMessage: String {
        switch self {
        case .noAction: return "Mark as reviewed with no action taken? The reporter will not be notified."
        case .warn: return "Issue a formal warning to the user? Strike count incremented, notification sent."
        case .delete: return "Permanently delete this content? This cannot be undone."
        case .deleteAndBan: return "Delete this content and permanently ban the user? Account deleted. Cannot be undone."
        }
    }
}
