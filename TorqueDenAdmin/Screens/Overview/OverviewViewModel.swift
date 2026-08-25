import Foundation

@MainActor
class OverviewViewModel: ObservableObject {
    func relativeTimestamp(from date: Date?) -> String {
        guard let date else { return "never" }
        let interval = -date.timeIntervalSinceNow
        switch interval {
        case ..<60: return "\(Int(interval))s ago"
        case ..<3600: return "\(Int(interval / 60))m ago"
        case ..<86400: return "\(Int(interval / 3600))h ago"
        default: return date.formatted(date: .abbreviated, time: .shortened)
        }
    }
}
