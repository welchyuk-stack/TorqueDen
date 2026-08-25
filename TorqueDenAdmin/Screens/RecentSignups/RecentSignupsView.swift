import SwiftUI

struct RecentSignupsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let signups = appState.adminStats?.recentSignups {
            List(signups) { signup in
                RecentSignupRowView(signup: signup)
            }
            .listStyle(.plain)
            .toolbar {
                ToolbarItem {
                    Button { Task { await appState.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "No Signups",
                systemImage: "person.2",
                description: Text("Refresh to load recent signups.")
            )
        }
    }
}
