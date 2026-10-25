import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(minWidth: 180, idealWidth: 200)

            Divider()

            detailContent
                .frame(minWidth: 600)
                .layoutPriority(1)
        }
        .onChange(of: appState.refreshInterval) { _, _ in
            appState.startAutoRefresh()
        }
        .onAppear {
            if appState.hasSavedKey && appState.adminStats == nil {
                Task { await appState.refresh() }
            }
            appState.startAutoRefresh()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch appState.selectedDestination {
        case .overview:
            OverviewView()
        case .moderation:
            ModerationView()
        case .content:
            ContentBrowserView()
        case .users:
            UsersView()
        case .broadcast:
            BroadcastView()
        case .recentSignups:
            RecentSignupsView()
        case .website:
            WebsiteView()
        case .challenges:
            ChallengesView()
        case .shotQueue:
            ShotThemeQueueView()
        case .settings:
            SettingsView()
        case nil:
            if appState.hasSavedKey {
                OverviewView()
            } else {
                SettingsView()
            }
        }
    }
}
