import SwiftUI

struct ContentTypeBadge: View {
    let type: String

    var body: some View {
        Text(type.prefix(1).uppercased())
            .font(.caption.weight(.bold))
            .foregroundColor(.white)
            .frame(width: 24, height: 24)
            .background(badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var badgeColor: Color {
        switch type {
        case "post": return .blue
        case "comment": return .indigo
        case "thread": return .purple
        case "reply": return .gray
        case "club": return .orange
        case "user": return .red
        default: return .secondary
        }
    }
}
