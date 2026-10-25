import SwiftUI
import ServiceManagement

@main
struct TorqueDenAdminApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.appState)
                .frame(minWidth: 820, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh") {
                    Task { await appDelegate.appState.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Moderation Queue") {
                    appDelegate.appState.selectedDestination = .moderation
                }
                .keyboardShortcut("1", modifiers: .command)
                Button("Broadcast") {
                    appDelegate.appState.selectedDestination = .broadcast
                }
                .keyboardShortcut("2", modifiers: .command)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
