import Foundation

@MainActor
class BroadcastViewModel: ObservableObject {
    @Published var title = ""
    @Published var body = ""
    @Published var isSending = false
    @Published var showConfirmation = false
    @Published var lastSuccess: Int?
    @Published var history: [BroadcastHistoryEntry] = []

    private let client = AdminAPIClient()
    private let historyKey = "broadcastHistory"

    init() {
        loadHistory()
    }

    func send() async {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSending = true
        do {
            let result = try await client.broadcast(title: title, message: body.isEmpty ? nil : body)
            let entry = BroadcastHistoryEntry(
                id: UUID(),
                title: title,
                sentAt: Date(),
                recipientCount: result.sent
            )
            history.insert(entry, at: 0)
            if history.count > 10 { history = Array(history.prefix(10)) }
            saveHistory()
            title = ""
            body = ""
            lastSuccess = result.sent
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                lastSuccess = nil
            }
        } catch {
            // Error handling
        }
        isSending = false
    }

    func refreshReceipts(_ entry: BroadcastHistoryEntry) async {
        guard let i = history.firstIndex(where: { $0.id == entry.id }) else { return }
        if let (read, total) = try? await client.fetchReadReceipts(sentAt: entry.sentAt) {
            history[i].readCount = read
            history[i].readTotal = total
            saveHistory()
        }
    }

    func recall(_ entry: BroadcastHistoryEntry) async {
        do {
            _ = try await client.recallBroadcast(sentAt: entry.sentAt)
            if let i = history.firstIndex(where: { $0.id == entry.id }) {
                history[i].recalled = true
                saveHistory()
            }
        } catch {}
    }

    func deleteFromHistory(_ entry: BroadcastHistoryEntry) {
        history.removeAll { $0.id == entry.id }
        saveHistory()
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([BroadcastHistoryEntry].self, from: data) else {
            return
        }
        history = decoded
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }
}
