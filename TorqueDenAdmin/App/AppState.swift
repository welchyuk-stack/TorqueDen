import Foundation
import Combine
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var adminStats: AdminStatsResponse?
    @Published var isLoading = false
    @Published var lastError: AdminError?
    @Published var openReportCount = 0
    @Published var selectedDestination: NavigationDestination?
    @Published var hasSavedKey: Bool = false

    @AppStorage("refreshInterval") var refreshInterval: Int = 300

    let api = AdminAPIClient()
    private var refreshTask: Task<Void, Never>?
    private var timestampTimer: Timer?

    init() {
        checkKey()
        setupTimestampTimer()
        setupNotificationObservers()
    }

    func checkKey() {
        hasSavedKey = (try? KeychainService.load(account: "adminKey")) != nil
        if !hasSavedKey {
            selectedDestination = .settings
        }
    }

    func refresh() async {
        guard hasSavedKey else {
            selectedDestination = .settings
            return
        }
        isLoading = true
        lastError = nil
        do {
            adminStats = try await api.fetchStats()
            openReportCount = adminStats?.moderation.openReports ?? 0
            selectedDestination = selectedDestination ?? .overview
        } catch let error as AdminError {
            lastError = error
            if case .unauthorized = error { hasSavedKey = false; selectedDestination = .settings }
        } catch {
            lastError = AdminError.networkError(error)
        }
        isLoading = false
    }

    func startAutoRefresh() {
        refreshTask?.cancel()
        guard refreshInterval > 0 else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self?.refreshInterval ?? 300) * 1_000_000_000)
                await self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func setupTimestampTimer() {
        timestampTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .init("moderationCountUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                if let count = notification.object as? Int {
                    self?.openReportCount = count
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: .init("navigateToModeration"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.selectedDestination = .moderation
            }
        }
        NotificationCenter.default.addObserver(
            forName: .init("keySaved"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hasSavedKey = true
                await self?.refresh()
            }
        }
    }
}
