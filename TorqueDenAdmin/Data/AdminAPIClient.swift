import Foundation

struct AdminAPIClient {
    static let functionURL = URL(string: "https://fadkprreszcttmjjybbz.supabase.co/functions/v1/admin-stats")!
    private let session = URLSession.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let encoder = JSONEncoder()

    func fetchStats() async throws -> AdminStatsResponse {
        try await get()
    }

    func resolveReport(id: String, status: ResolveStatus) async throws -> some Decodable {
        struct EmptyResponse: Codable {}
        return try await post(EmptyResponse.self, body: [
            "action": "resolve_report" as String,
            "reportId": id,
            "status": status.rawValue,
        ])
    }

    func warnUser(reportId: String) async throws -> WarnResult {
        try await post(WarnResult.self, body: [
            "action": "warn" as String,
            "reportId": reportId,
        ])
    }

    func deleteContent(reportId: String) async throws -> ActionResult {
        try await post(ActionResult.self, body: [
            "action": "delete_content" as String,
            "reportId": reportId,
        ])
    }

    func deleteAndBan(reportId: String) async throws -> ActionResult {
        try await post(ActionResult.self, body: [
            "action": "delete_and_ban" as String,
            "reportId": reportId,
        ])
    }

    func fetchReadReceipts(sentAt: Date) async throws -> (read: Int, total: Int) {
        struct Body: Encodable { let action = "fetch_read_receipts"; let sentAt: String }
        struct Result: Decodable { let read: Int; let total: Int }
        let iso = ISO8601DateFormatter().string(from: sentAt)
        let r: Result = try await post(Result.self, body: Body(sentAt: iso))
        return (r.read, r.total)
    }

    func fetchUsers(page: Int) async throws -> UsersPage {
        struct Body: Encodable { let action = "fetch_users"; let page: Int }
        return try await post(UsersPage.self, body: Body(page: page))
    }

    func recallBroadcast(sentAt: Date) async throws -> Int {
        struct Body: Encodable {
            let action = "recall_broadcast"
            let sentAt: String
        }
        struct Result: Decodable { let deleted: Int }
        let iso = ISO8601DateFormatter().string(from: sentAt)
        let r: Result = try await post(Result.self, body: Body(sentAt: iso))
        return r.deleted
    }

    func broadcast(title: String, message: String?) async throws -> BroadcastResult {
        var body: [String: String] = ["action": "broadcast", "title": title]
        if let message { body["message"] = message }
        return try await post(BroadcastResult.self, body: body)
    }

    func fetchContent(contentType: String, page: Int) async throws -> ContentPage {
        struct Body: Encodable {
            let action = "fetch_content"
            let contentType: String
            let page: Int
        }
        return try await post(ContentPage.self, body: Body(contentType: contentType, page: page))
    }

    func deleteItem(contentType: String, itemId: String) async throws {
        struct Body: Encodable {
            let action = "delete_item"
            let contentType: String
            let itemId: String
        }
        struct Empty: Codable {}
        let _: Empty = try await post(Empty.self, body: Body(contentType: contentType, itemId: itemId))
    }

    // MARK: - Challenges

    func fetchChallenges() async throws -> [AdminChallenge] {
        struct Body: Encodable { let action = "fetch_challenges" }
        let r: ChallengesResponse = try await post(ChallengesResponse.self, body: Body())
        return r.challenges
    }

    func fetchChallengeEntries(tag: String, startsAt: Date, endsAt: Date) async throws -> [AdminEntry] {
        struct Body: Encodable { let action = "fetch_challenge_entries"; let tag: String; let starts_at: String; let ends_at: String }
        let fmt = ISO8601DateFormatter()
        let r: EntriesResponse = try await post(EntriesResponse.self, body: Body(tag: tag, starts_at: fmt.string(from: startsAt), ends_at: fmt.string(from: endsAt)))
        return r.entries
    }

    func setChallengeWinner(challengeId: String, entryId: String, carId: String?) async throws {
        struct Body: Encodable { let action = "set_challenge_winner"; let challengeId: String; let entryId: String; let carId: String? }
        struct OK: Codable {}
        let _: OK = try await post(OK.self, body: Body(challengeId: challengeId, entryId: entryId, carId: carId))
    }

    func createChallenge(title: String, emoji: String, tag: String, description: String, startsAt: Date, endsAt: Date) async throws -> AdminChallenge {
        struct Body: Encodable { let action = "create_challenge"; let title: String; let emoji: String; let tag: String; let description: String; let starts_at: String; let ends_at: String }
        struct Resp: Codable { let challenge: AdminChallenge }
        let fmt = ISO8601DateFormatter()
        let r: Resp = try await post(Resp.self, body: Body(title: title, emoji: emoji, tag: tag, description: description, starts_at: fmt.string(from: startsAt), ends_at: fmt.string(from: endsAt)))
        return r.challenge
    }

    func updateChallenge(id: String, title: String, emoji: String, tag: String, description: String, startsAt: Date, endsAt: Date) async throws {
        struct Body: Encodable { let action = "update_challenge"; let challengeId: String; let title: String; let emoji: String; let tag: String; let description: String; let starts_at: String; let ends_at: String }
        struct OK: Codable {}
        let fmt = ISO8601DateFormatter()
        let _: OK = try await post(OK.self, body: Body(challengeId: id, title: title, emoji: emoji, tag: tag, description: description, starts_at: fmt.string(from: startsAt), ends_at: fmt.string(from: endsAt)))
    }

    func deleteChallenge(id: String) async throws {
        struct Body: Encodable { let action = "delete_challenge"; let challengeId: String }
        struct OK: Codable {}
        let _: OK = try await post(OK.self, body: Body(challengeId: id))
    }

    // MARK: - Shot Theme Queue

    func fetchShotThemes() async throws -> [ShotTheme] {
        struct Body: Encodable { let action = "fetch_shot_themes" }
        let r: ShotThemesResponse = try await post(ShotThemesResponse.self, body: Body())
        return r.themes
    }

    func createShotTheme(title: String, emoji: String, tag: String, description: String) async throws -> ShotTheme {
        struct Body: Encodable { let action = "create_shot_theme"; let title: String; let emoji: String; let tag: String; let description: String }
        struct Resp: Codable { let theme: ShotTheme }
        let r: Resp = try await post(Resp.self, body: Body(title: title, emoji: emoji, tag: tag, description: description))
        return r.theme
    }

    func updateShotTheme(id: String, title: String, emoji: String, tag: String, description: String) async throws {
        struct Body: Encodable { let action = "update_shot_theme"; let themeId: String; let title: String; let emoji: String; let tag: String; let description: String }
        struct OK: Codable {}
        let _: OK = try await post(OK.self, body: Body(themeId: id, title: title, emoji: emoji, tag: tag, description: description))
    }

    func deleteShotTheme(id: String) async throws {
        struct Body: Encodable { let action = "delete_shot_theme"; let themeId: String }
        struct OK: Codable {}
        let _: OK = try await post(OK.self, body: Body(themeId: id))
    }

    func reorderShotThemes(orderedIds: [String]) async throws {
        struct Body: Encodable { let action = "reorder_shot_themes"; let orderedIds: [String] }
        struct OK: Codable {}
        let _: OK = try await post(OK.self, body: Body(orderedIds: orderedIds))
    }

    // MARK: - Private

    private func adminKeyHeader() throws -> String {
        try KeychainService.load(account: "adminKey")
    }

    private func get<T: Decodable>() async throws -> T where T: Sendable {
        var request = URLRequest(url: Self.functionURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(try adminKeyHeader(), forHTTPHeaderField: "x-admin-key")
        request.httpMethod = "GET"
        return try await execute(request)
    }

    private func post<T: Decodable>(_ type: T.Type, body: some Encodable) async throws -> T where T: Sendable {
        var request = URLRequest(url: Self.functionURL)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try adminKeyHeader(), forHTTPHeaderField: "x-admin-key")
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(AnyEncodable(body))
        return try await execute(request)
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T where T: Sendable {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AdminError.networkError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AdminError.serverError("Invalid response")
        }
        switch httpResponse.statusCode {
        case 200:
            return try decoder.decode(T.self, from: data)
        case 401:
            throw AdminError.unauthorized
        default:
            let msg = (try? decoder.decode(ErrorBody.self, from: data))?.message ?? "Server error (\(httpResponse.statusCode))"
            throw AdminError.serverError(msg)
        }
    }
}

private struct ErrorBody: Decodable { let message: String }

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ wrapped: some Encodable) {
        _encode = { try wrapped.encode(to: $0) }
    }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
