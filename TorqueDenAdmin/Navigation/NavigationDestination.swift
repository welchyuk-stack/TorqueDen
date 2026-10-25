import Foundation

enum NavigationDestination: String, CaseIterable, Identifiable {
    case overview
    case moderation
    case content
    case users
    case broadcast
    case recentSignups
    case website
    case challenges
    case shotQueue
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .moderation: return "Moderation"
        case .content: return "Content"
        case .users: return "Users"
        case .broadcast: return "Broadcast"
        case .recentSignups: return "Recent Signups"
        case .website: return "Website"
        case .challenges: return "Challenges"
        case .shotQueue: return "Shot Queue"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "chart.bar.fill"
        case .moderation: return "exclamationmark.shield.fill"
        case .content: return "doc.text.magnifyingglass"
        case .users: return "person.3.fill"
        case .broadcast: return "megaphone.fill"
        case .recentSignups: return "person.2.fill"
        case .website: return "globe"
        case .challenges: return "trophy.fill"
        case .shotQueue: return "camera.aperture"
        case .settings: return "gearshape.fill"
        }
    }
}
