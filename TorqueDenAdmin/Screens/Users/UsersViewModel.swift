import Foundation

@MainActor
class UsersViewModel: ObservableObject {
    @Published var users: [AdminUser] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?
    @Published var hasMore = false

    private var currentPage = 0
    private let client = AdminAPIClient()

    func load() async {
        currentPage = 0
        users = []
        error = nil
        isLoading = true
        defer { isLoading = false }
        await fetchPage(0)
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await fetchPage(currentPage + 1)
    }

    private func fetchPage(_ page: Int) async {
        do {
            let result = try await client.fetchUsers(page: page)
            if page == 0 {
                users = result.users
            } else {
                users.append(contentsOf: result.users)
            }
            hasMore = result.hasMore
            currentPage = page
        } catch {
            self.error = error.localizedDescription
        }
    }
}
