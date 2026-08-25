import AppKit
import Foundation
import BackgroundTasks
import UserNotifications

actor ModerationPollService {
    static let shared = ModerationPollService()
    private var lastKnownCount = 0
    private var isPolling = false

    func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        Task { await pollLoop() }
    }

    func stopPolling() { isPolling = false }

    private func pollLoop() async {
        while isPolling {
            do {
                let client = AdminAPIClient()
                let stats = try await client.fetchStats()
                let count = stats.moderation.openReports
                if count > lastKnownCount {
                    await sendNotification(count: count)
                }
                lastKnownCount = count
                await updateBadge(count: count)
                NotificationCenter.default.post(name: .init("moderationCountUpdated"), object: count)
            } catch { /* silent retry */ }
            try? await Task.sleep(nanoseconds: 120_000_000_000)
        }
    }

    private func sendNotification(count: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Moderation Queue"
        content.body = "\(count) open report\(count == 1 ? "" : "s") waiting for review."
        content.sound = .default
        content.badge = NSNumber(value: count)
        content.categoryIdentifier = "MODERATION_QUEUE"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
        NotificationCenter.default.post(name: .init("moderationCountUpdated"), object: count)
    }

    @MainActor
    private func updateBadge(count: Int) {
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }
}
