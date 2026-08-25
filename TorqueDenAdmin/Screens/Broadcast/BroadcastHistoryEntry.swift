import Foundation

struct BroadcastHistoryEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let sentAt: Date
    let recipientCount: Int
    var recalled: Bool = false
    var readCount: Int? = nil
    var readTotal: Int? = nil
}
