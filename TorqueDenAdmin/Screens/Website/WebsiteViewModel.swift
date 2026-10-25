import Foundation

@MainActor
class WebsiteViewModel: ObservableObject {
    @Published var stats: CloudflareStats?
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectedDays = 30

    var hasCredentials: Bool {
        (try? KeychainService.load(account: "cloudflareToken")) != nil &&
        (try? KeychainService.load(account: "cloudflareZoneId")) != nil
    }

    func load() async {
        guard hasCredentials else {
            error = CloudflareError.missingCredentials.localizedDescription
            return
        }
        isLoading = true
        error = nil
        do {
            let client = try CloudflareAPIClient()
            stats = try await client.fetchStats(days: selectedDays)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
