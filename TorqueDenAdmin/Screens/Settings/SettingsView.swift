import SwiftUI
import ServiceManagement
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var adminKey = ""
    @State private var cloudflareToken = ""
    @State private var cloudflareZoneId = ""
    @State private var showAdminKey = false
    @State private var showCloudflareToken = false
    @State private var adminKeyStatus: KeyStatus = .unknown
    @State private var cloudflareStatus: KeyStatus = .unknown
    @State private var notificationEnabled = false
    @State private var launchAtLogin = false

    enum KeyStatus: String {
        case saved = "Saved in Keychain"
        case notSaved = "No key saved"
        case unknown = ""
    }

    var body: some View {
        Form {
            // Credentials
            Section("Credentials") {
                HStack {
                    if showAdminKey {
                        TextField("Admin Key", text: $adminKey)
                    } else {
                        SecureField("Admin Key", text: $adminKey)
                    }
                    Button(showAdminKey ? "Hide" : "Show") { showAdminKey.toggle() }
                        .buttonStyle(.borderless)
                }
                HStack {
                    Button("Save") { saveAdminKey() }
                    statusBadge(adminKeyStatus)
                }

                HStack {
                    if showCloudflareToken {
                        TextField("Cloudflare API Token", text: $cloudflareToken)
                    } else {
                        SecureField("Cloudflare API Token", text: $cloudflareToken)
                    }
                    Button(showCloudflareToken ? "Hide" : "Show") { showCloudflareToken.toggle() }
                        .buttonStyle(.borderless)
                }
                TextField("Cloudflare Zone ID", text: $cloudflareZoneId)
                Text("Optional — enables the Website tab. Token needs Zone:Read + Analytics:Read permissions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Button("Save") { saveCloudflare() }
                    statusBadge(cloudflareStatus)
                }
            }

            // Notifications
            Section("Notifications") {
                Toggle("Report queue notifications", isOn: $notificationEnabled)
                    .onChange(of: notificationEnabled) { _, newValue in
                        if newValue {
                            Task {
                                let center = UNUserNotificationCenter.current()
                                let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                                if granted != true {
                                    notificationEnabled = false
                                }
                            }
                        }
                    }
            }

            // Refresh Interval
            Section("Refresh Interval") {
                Picker("Auto-refresh", selection: $appState.refreshInterval) {
                    Text("Off").tag(0)
                    Text("2 min").tag(120)
                    Text("5 min").tag(300)
                    Text("15 min").tag(900)
                }
                Text("The moderation queue is always polled every 2 minutes regardless of this setting.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // General
            Section("General") {
                Link("Open web admin panel", destination: URL(string: "https://torquedenapp.com/admin/")!)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {}
                    }
            }

            // About
            Section("About") {
                HStack {
                    Text("TorqueDen Admin")
                    Spacer()
                    Text("Version 1.0 (build \(buildNumber))")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            adminKey = (try? KeychainService.load(account: "adminKey")) ?? ""
            cloudflareToken = (try? KeychainService.load(account: "cloudflareToken")) ?? ""
            cloudflareZoneId = (try? KeychainService.load(account: "cloudflareZoneId")) ?? ""
            adminKeyStatus = adminKey.isEmpty ? .notSaved : .saved
            cloudflareStatus = (cloudflareToken.isEmpty || cloudflareZoneId.isEmpty) ? .notSaved : .saved
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private var buildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }

    private func statusBadge(_ status: KeyStatus) -> some View {
        Group {
            switch status {
            case .saved:
                Label("Saved in Keychain", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            case .notSaved:
                Label("No key saved", systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            case .unknown:
                EmptyView()
            }
        }
    }

    private func saveAdminKey() {
        guard !adminKey.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        try? KeychainService.save(adminKey, account: "adminKey")
        adminKeyStatus = .saved
        NotificationCenter.default.post(name: .init("keySaved"), object: nil)
        Task { await appState.refresh() }
    }

    private func saveCloudflare() {
        let token = cloudflareToken.trimmingCharacters(in: .whitespaces)
        let zoneId = cloudflareZoneId.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty, !zoneId.isEmpty else { return }
        try? KeychainService.save(token, account: "cloudflareToken")
        try? KeychainService.save(zoneId, account: "cloudflareZoneId")
        cloudflareStatus = .saved
    }
}
