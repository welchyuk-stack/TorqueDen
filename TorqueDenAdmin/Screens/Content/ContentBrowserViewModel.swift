import Foundation

struct ContentItem: Identifiable, Decodable, Sendable {
    let id: String
    let preview: String
    let createdAt: Date
    let authorId: String?
    let username: String
}

struct ContentPage: Decodable, Sendable {
    let items: [ContentItem]
    let page: Int
    let hasMore: Bool
}

enum ContentType: String, CaseIterable {
    case post, comment, thread, reply

    var label: String {
        switch self {
        case .post:    return "Posts"
        case .comment: return "Comments"
        case .thread:  return "Threads"
        case .reply:   return "Replies"
        }
    }
}

@MainActor
class ContentBrowserViewModel: ObservableObject {
    @Published var items: [ContentItem] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?
    @Published var selectedType: ContentType = .post
    @Published var hasMore = false

    private var currentPage = 0
    private let client = AdminAPIClient()

    func load() async {
        currentPage = 0
        items = []
        hasMore = false
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

    func delete(_ item: ContentItem) async {
        do {
            try await client.deleteItem(contentType: selectedType.rawValue, itemId: item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fetchPage(_ page: Int) async {
        do {
            let result: ContentPage = try await client.fetchContent(
                contentType: selectedType.rawValue, page: page
            )
            if page == 0 {
                items = result.items
            } else {
                items.append(contentsOf: result.items)
            }
            hasMore = result.hasMore
            currentPage = page
        } catch {
            self.error = error.localizedDescription
        }
    }
}
