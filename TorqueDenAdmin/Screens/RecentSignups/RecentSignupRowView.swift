import SwiftUI

struct RecentSignupRowView: View {
    let signup: RecentSignup

    private let colors: [Color] = [.red, .orange, .green, .blue, .purple, .pink, .indigo, .teal]

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(avatarColor)
                .frame(width: 32, height: 32)
                .overlay {
                    Text(signup.username.prefix(1).uppercased())
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                        .font(.caption)
                }
            Text("@\(signup.username)")
                .font(.subheadline)
            Spacer()
            Text(timeString)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var avatarColor: Color {
        let hash = signup.username.utf8.reduce(0) { $0 + Int($1) }
        return colors[hash % colors.count]
    }

    private var timeString: String {
        let interval = -signup.createdAt.timeIntervalSinceNow
        if interval < 86400 {
            return signup.createdAt.formatted(.relative(presentation: .numeric))
        }
        return signup.createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}
