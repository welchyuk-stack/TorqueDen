import Foundation

// MARK: - Top Level
struct AdminStatsResponse: Codable, Sendable {
    let generatedAt: Date
    let users: UserStats
    let clubs: ClubStats
    let content: ContentStats
    let subscribers: SubscriberStats
    let moderation: ModerationStats
    let reports: [Report]
    let recentSignups: [RecentSignup]
    let usage: UsageStats?
}

struct UserStats: Codable, Sendable {
    let total: Int
    let new7D: Int
    let new30D: Int
}
struct ClubStats: Codable, Sendable { let total: Int; let `public`, `private`: Int }
struct ContentStats: Codable, Sendable { let cars, posts, comments, reactions: Int }
struct SubscriberStats: Codable, Sendable { let premium, partner: Int }
struct ModerationStats: Codable, Sendable { let openReports: Int }

struct Report: Codable, Identifiable, Sendable {
    let id, targetType, targetId, reason, status, reporterId, reporterUsername: String
    let note, contentPreview: String?
    let createdAt: Date
    let strikeCount: Int
}

struct RecentSignup: Codable, Identifiable, Sendable {
    var id: String { username }
    let username: String
    let createdAt: Date
}

struct UsageStats: Codable, Sendable {
    let dbSizeBytes: Int?
    let storageSizeBytes: Int?
    let limits: UsageLimits
}

struct UsageLimits: Codable, Sendable {
    let dbSizeBytes: Int
    let storageSizeBytes: Int
}

// MARK: - Users
struct AdminUser: Codable, Identifiable, Sendable {
    let id: String
    let username: String?
    let createdAt: Date
    let lastSignInAt: Date?
}

struct UsersPage: Codable, Sendable {
    let users: [AdminUser]
    let hasMore: Bool
}

// MARK: - Challenges
struct AdminChallenge: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let emoji: String
    let tag: String
    let description: String
    let startsAt: Date
    let endsAt: Date
    let winnerEntryId: String?
    let winnerAnnounced: Bool
    let createdAt: Date

    var isActive: Bool {
        let now = Date()
        return now >= startsAt && now <= endsAt
    }
    var isUpcoming: Bool { Date() < startsAt }
    var isEnded: Bool { Date() > endsAt }

    var statusLabel: String {
        if isActive { return "Active" }
        if isUpcoming { return "Upcoming" }
        return "Ended"
    }
    var statusColor: String {
        if isActive { return "green" }
        if isUpcoming { return "blue" }
        return "secondary"
    }
}

struct ChallengesResponse: Codable, Sendable { let challenges: [AdminChallenge] }

// MARK: - Shot Theme Queue
struct ShotTheme: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let emoji: String
    let tag: String
    let description: String
    let queuePosition: Int?
    let createdAt: Date
}

struct ShotThemesResponse: Codable, Sendable { let themes: [ShotTheme] }

struct AdminEntry: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let body: String?
    let createdAt: Date
    let car: AdminEntryCar?
    let postMedia: [AdminEntryMedia]?
    let postLikes: [AdminEntryLike]?

    var likeCount: Int { postLikes?.count ?? 0 }
    var firstImageUrl: String? { postMedia?.first(where: { $0.kind == "image" })?.url }
}

struct AdminEntryCar: Codable, Sendable {
    let id: String
    let make: String
    let model: String
    let nickname: String?
    let photoUrl: String?
    let ownerId: String?
    var title: String { nickname ?? "\(make) \(model)" }
}

struct AdminEntryMedia: Codable, Sendable { let id: String; let url: String; let kind: String }
struct AdminEntryLike: Codable, Sendable { let userId: String }
struct EntriesResponse: Codable, Sendable { let entries: [AdminEntry] }

// MARK: - Report Actions
struct WarnResult: Codable, Sendable { let ok: Bool; let strike: Int }
struct ActionResult: Codable, Sendable { let ok: Bool; let deleted: Bool; let banned: Bool }
struct BroadcastResult: Codable, Sendable { let ok: Bool; let sent: Int }

// MARK: - Enums
enum ResolveStatus: String, Codable, Sendable { case resolved, dismissed }
enum AdminError: LocalizedError, Sendable {
    case unauthorized
    case serverError(String)
    case networkError(Error)
    case missingKey
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Invalid admin key. Check Settings."
        case .serverError(let msg): return msg
        case .networkError(let e): return e.localizedDescription
        case .missingKey: return "No admin key saved."
        }
    }
    static func == (lhs: AdminError, rhs: AdminError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized): return true
        case (.missingKey, .missingKey): return true
        case (.serverError(let a), .serverError(let b)): return a == b
        default: return false
        }
    }
}
