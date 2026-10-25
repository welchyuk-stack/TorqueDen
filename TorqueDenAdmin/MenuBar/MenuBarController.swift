import Cocoa
import SwiftUI

class MenuBarController {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    init(appState: AppState) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "TorqueDen Admin")
            button.action = #selector(togglePopover)
            button.target = self
        }
        setupPopover(appState: appState)
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateTitle),
            name: .init("moderationCountUpdated"), object: nil
        )
    }

    private func setupPopover(appState: AppState) {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 280, height: 120)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView().environmentObject(appState)
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func updateTitle(_ notification: Notification) {
        if let count = notification.object as? Int, count > 0 {
            statusItem?.button?.title = "⚠ \(count)"
        } else {
            statusItem?.button?.title = ""
        }
    }
}

struct MenuBarPopoverView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            Text("TorqueDen Admin")
                .font(.headline)
            if appState.openReportCount > 0 {
                Label("\(appState.openReportCount) open reports", systemImage: "exclamationmark.shield")
                    .foregroundColor(.orange)
            } else {
                Label("No open reports", systemImage: "checkmark.shield")
                    .foregroundColor(.green)
            }
            Button("Open Admin") {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
        .padding()
        .frame(width: 280)
    }
}
