import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            Text("TorqueDen Admin")
                .font(.headline)
                .foregroundColor(.secondary)

            ForEach(NavigationDestination.allCases) { dest in
                Button {
                    appState.selectedDestination = dest
                } label: {
                    HStack {
                        Label(dest.label, systemImage: dest.systemImage)
                        Spacer()
                        if dest == .moderation && appState.openReportCount > 0 {
                            Text("\(appState.openReportCount)")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.15), in: Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    appState.selectedDestination == dest
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear
                )
            }
        }
        .listStyle(.sidebar)
    }
}
