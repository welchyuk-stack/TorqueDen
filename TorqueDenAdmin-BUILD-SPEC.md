# TorqueDenAdmin — macOS Native App Build Spec

**Version:** 1.0
**Date:** 2026-07-19

---

## 1. App Identity & Distribution

| Field | Value |
|---|---|
| Bundle ID | `com.torquedenapp.admin` |
| Display name | TorqueDen Admin |
| Minimum macOS | 14.0 |
| Distribution | Developer ID — direct download, NOT Mac App Store |
| Code signing | Developer ID Application certificate |
| Notarisation | Yes — `xcrun notarytool submit` |
| Architecture | Apple Silicon + Intel universal binary |

### Admin Key Storage

Admin key (`ADMIN_DASHBOARD_KEY`) and Supabase PAT stored exclusively in macOS Keychain via `SecItemAdd` / `SecItemCopyMatching`. Service name: `com.torquedenapp.admin`, accounts: `adminKey` and `supabasePAT`. On first launch the app shows Settings with the key field focused.

### Auto-Launch on Login

`SMAppService.mainApp` toggle in Settings (macOS 13+ API). No LaunchAgent plist needed.

---

## 2. Navigation — NavigationSplitView

Three-column `NavigationSplitView`, sidebar–detail style.

```
┌──────────────────────────────────────────────────────────────┐
│  Sidebar (180 pt)           │  Content area (fills remainder) │
│  ─────────────────          │                                  │
│  TorqueDen Admin            │  (selected screen renders here)  │
│  ─ Overview            📊   │                                  │
│  ─ Moderation    [badge] 🚨 │                                  │
│  ─ Broadcast           📣   │                                  │
│  ─ Recent Signups      👥   │                                  │
│  ──────────────────         │                                  │
│  ─ Settings            ⚙️   │                                  │
└──────────────────────────────────────────────────────────────┘
```

| Label | SF Symbol | Badge rule |
|---|---|---|
| Overview | `chart.bar.fill` | None |
| Moderation | `exclamationmark.shield.fill` | Red badge showing `openReportCount` when > 0 |
| Broadcast | `megaphone.fill` | None |
| Recent Signups | `person.2.fill` | None |
| Settings | `gearshape.fill` | Orange dot if no admin key saved |

Sidebar min width 180 pt, content min width 600 pt, minimum window size `820 × 560`.

Default selection on launch: Overview (if key stored) or Settings (if no key).

---

## 3. Screens

---

### 3.1 Overview / Dashboard

Vertically scrollable `ScrollView` with `LazyVStack(spacing: 24)`, padded 24 pt all sides.

**Header bar** (pinned via `safeAreaInset`):
```
[TorqueDen Admin logo]   [Updated 2m ago]   [↻ Refresh]
```

**Stat tile groups** — `LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12)`:

| Section | Tiles |
|---|---|
| Users | Total Users · New (7 days) · New (30 days) |
| Clubs | Total Clubs · Public · Private |
| Content & Engagement | Cars · Build Posts · Comments · Reactions |
| Revenue (Subscribers) | Premium · Partner |

Footer note: "Subscriber counts only. Revenue figures live in RevenueCat and AdMob." with tappable `Link` views.

**`StatTileView`:** `RoundedRectangle(cornerRadius: 12)`, 11pt caption label (uppercase, secondary), 28pt bold value. Animate value changes with `withAnimation(.easeOut)`.

#### Supabase Usage Section

Section header: "Supabase Usage (Free Tier)"

If `data.usage == nil`: "Add SUPABASE_PAT in Settings to enable usage tracking."

If present — 5 `UsageRowView` items:

```
Database size              142.3 MB / 500 MB · 28%
[████████░░░░░░░░░░░░░░░░]
367.7 MB remaining
```

- Track: `RoundedRectangle(cornerRadius: 4)`, height 7, `.quaternaryLabel` fill
- Fill colour thresholds: `< 70%` → ember orange · `70–90%` → yellow · `≥ 90%` → red
- Animated width via `GeometryReader`
- Value label: tabular-nums, right-aligned

**Free-tier limits:**

| Metric | Limit |
|---|---|
| Database size | 500 MB |
| Storage | 1 GB |
| Egress bandwidth | 5 GB / month |
| Monthly active users | 50,000 |
| Edge fn invocations | 500,000 / month |

**Auto-refresh:** `Timer.publish(every: refreshInterval)` — driven by Settings preference (Off / 2 min / 5 min / 15 min). Relative timestamp refreshes every 30 s via lightweight second timer (no network).

---

### 3.2 Moderation Queue

`HSplitView` — left panel min 280 pt, right panel min 380 pt. Split position persisted in `AppStorage("moderation.splitFraction")`.

#### Left Panel — Report List

`List(selection: $selectedReportID)` with `ScrollViewReader`.

Each `ReportListRowView`:
```
[badge: post]  Harassment
"I'm going to find you and…"           [● 2 strikes]
@john_turbo · 3h ago
```

Badge colours by type: `post` → blue · `comment` → indigo · `thread` → purple · `reply` → gray · `club` → orange · `user` → red.

Empty state: `ContentUnavailableView("No open reports", systemImage: "checkmark.shield")`.

#### Right Panel — Report Detail

No selection: `ContentUnavailableView("Select a report", systemImage: "arrow.left")`.

When selected — `ReportDetailView`:

**Full content preview:** `GroupBox("Reported Content")` — scrollable, max ~8 lines. Shows full `content_preview`, or "User profile reported directly" for `target_type == "user"`.

**Reported user card:** `GroupBox("Reported User")` — avatar initial circle, username (bold), "Member since [date]", strike count (⚠ orange/red if > 0, green "No strikes" if 0).

**Report metadata:** reason, note, reported-at timestamp, target type.

**Action Toolbar** (`.toolbar` on detail view):

| Action | Shortcut | Style |
|---|---|---|
| No Action | `⌘D` | Secondary |
| Warn User | `⌘W` | Yellow tinted |
| Delete Content | `⌘⌫` | Red tinted |
| Delete + Ban | `⌘⇧B` | Filled red, destructive |

All actions show a SwiftUI `.confirmationDialog` (not `NSAlert`).

**Confirmation dialogs:**
- **No Action:** "Mark as reviewed with no action taken? The reporter will not be notified."
- **Warn:** "Issue a formal warning to @username? Strike count incremented, notification sent."
- **Delete:** "Permanently delete this [type]? This cannot be undone."
- **Delete + Ban:** "Delete this content and permanently ban @username? Account deleted. Cannot be undone."

**Post-action:** Remove row from local array → auto-select next report → decrement badge. On error: inline banner with "Try Again".

#### Dock Badge + Menu Bar

`NSApp.dockTile.badgeLabel` = open count string when > 0, cleared when 0.

`NSStatusItem` in menu bar — tyre-logo as template image, title `"⚠ 3"` when reports pending. Clicking brings app to front and navigates to Moderation.

#### Background Polling

`ModerationPollService` (Swift `actor`) with `NSBackgroundActivityScheduler`, interval 120 s, tolerance 30 s. Polls even when app is backgrounded. On `newCount > previousCount`: fires `UNUserNotification` + posts `NotificationCenter` event to update Dock/menu bar immediately.

---

### 3.3 Broadcast

`Form` in padded `VStack`, max width 600 pt, centred.

```
BROADCAST MESSAGE
────────────────────────────────────────
[Title field                    ] 0/80
[Body textarea                         ]
[                               0/300  ]

[Send to all 4,201 users]
────────────────────────────────────────
SENT HISTORY
• "New club system is live!"  → 4,201 users  Jul 14 14:32
• "TorqueDen v2.1 is out!"   → 3,877 users  Jun 28 09:10
```

- Title: `TextField` with live character counter, turns red approaching limit
- Body: `TextEditor` with placeholder overlay, min 80 pt height, expands to 160 pt
- Send button: disabled while sending, shows `ProgressView` overlay
- Confirmation dialog before send; inline green success banner ("Sent to N users") auto-dismisses after 4 s
- History: `[BroadcastHistoryEntry]` stored in `UserDefaults`, max 10 entries, `Codable`

```swift
struct BroadcastHistoryEntry: Codable, Identifiable {
    let id: UUID
    let title: String
    let sentAt: Date
    let recipientCount: Int
}
```

---

### 3.4 Recent Signups

Read-only `List`, 10 rows max (as returned by API).

Each `RecentSignupRowView`:
```
[A]  @alice_mustang                Jul 14 2026, 2:31 PM
[B]  @bob_turbo                    3 hours ago
```

- Avatar: 32 pt circle, deterministic colour from username hash, uppercase first letter in white
- Time: relative if < 24 h, absolute otherwise
- Non-selectable, no pagination
- Refresh toolbar button triggers full stats reload

---

### 3.5 Settings

`Form` with grouped sections.

**Credentials:**
- Admin Key: `SecureField` + reveal toggle (eye icon) + Keychain save button. Status: green "Saved in Keychain" / red "No key saved"
- Supabase PAT: same pattern. Label: "Optional — enables usage tracking on the Overview screen."

**Notifications:**
- Toggle "Report queue notifications" — calls `requestAuthorization` on enable; if denied, shows "Enable in System Settings > Notifications" note

**Refresh Interval:**
- `Picker` — Off / 2 min / 5 min / 15 min (stored in `AppStorage("refreshInterval")`)
- Note: "The moderation queue is always polled every 2 minutes regardless of this setting."

**General:**
- "Open web admin panel" `Link` → `https://torquedenapp.com/admin/`
- "Launch at login" toggle → `SMAppService.mainApp`

**About:**
- "TorqueDen Admin — Version 1.0 (build 42)" from `Bundle.main.infoDictionary`

---

## 4. Data Layer

### 4.1 `AdminAPIClient`

```swift
struct AdminAPIClient {
    static let functionURL = URL(string: "https://fadkprreszcttmjjybbz.supabase.co/functions/v1/admin-stats")!

    func fetchStats() async throws -> AdminStatsResponse
    func resolveReport(id: String, status: ResolveStatus) async throws
    func warnUser(reportId: String) async throws -> WarnResult
    func deleteContent(reportId: String) async throws -> ActionResult
    func deleteAndBan(reportId: String) async throws -> ActionResult
    func broadcast(title: String, message: String?) async throws -> BroadcastResult

    private func adminKeyHeader() throws -> String  // Keychain read, throws if missing
    private func post<T: Decodable>(_ body: Encodable) async throws -> T
    private func get<T: Decodable>() async throws -> T
}
```

HTTP 401 → `AdminError.unauthorized` (redirects to Settings). HTTP 4xx/5xx → `AdminError.serverError(String)`.

### 4.2 Response Models (all `Codable, Sendable`)

```swift
struct AdminStatsResponse: Codable {
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

struct UserStats: Codable { let total, new7d, new30d: Int }
struct ClubStats: Codable { let total, `public`, `private`: Int }
struct ContentStats: Codable { let cars, posts, comments, reactions: Int }
struct SubscriberStats: Codable { let premium, partner: Int }
struct ModerationStats: Codable { let openReports: Int }

struct Report: Codable, Identifiable {
    let id, targetType, targetId, reason, status, reporterId, reporterUsername: String
    let note, contentPreview: String?
    let createdAt: Date
    let strikeCount: Int
}

struct RecentSignup: Codable, Identifiable {
    var id: String { username }
    let username: String
    let createdAt: Date
}

struct UsageStats: Codable {
    let dbSizeBytes, storageSizeBytes, egressBytes: Int?
    let monthlyActiveUsers, funcInvocations: Int?
    let limits: UsageLimits
}

struct UsageLimits: Codable {
    let dbSizeBytes, storageSizeBytes, egressBytes: Int
    let monthlyActiveUsers, funcInvocations: Int
}

struct WarnResult: Codable { let ok: Bool; let strike: Int }
struct ActionResult: Codable { let ok: Bool; let deleted: Bool; let banned: Bool }
struct BroadcastResult: Codable { let ok: Bool; let sent: Int }

enum ResolveStatus: String, Codable { case resolved, dismissed }
enum AdminError: LocalizedError { case unauthorized, serverError(String), networkError(Error), missingKey }
```

`JSONDecoder`: `.convertFromSnakeCase` key strategy + `.iso8601` date strategy.

### 4.3 `KeychainService`

```swift
struct KeychainService {
    static let serviceName = "com.torquedenapp.admin"
    static func save(_ value: String, account: String) throws
    static func load(account: String) throws -> String  // throws .missingKey if absent
    static func delete(account: String)
}
```

### 4.4 ViewModels

```
AppState (ObservableObject, @EnvironmentObject)
  ├── adminStats: AdminStatsResponse?
  ├── isLoading: Bool
  ├── lastError: AdminError?
  ├── openReportCount: Int        (drives Dock badge + menu bar)
  ├── refreshInterval: Int        (AppStorage-backed)
  └── func refresh() async

OverviewViewModel     — owns 5-min refresh Timer + 30-s timestamp timer
ModerationViewModel   — local [Report] array, selectedReportID, action methods
BroadcastViewModel    — title/body fields, send(), UserDefaults history
```

All `@Published` mutations on `@MainActor`. `AdminAPIClient` injected via `EnvironmentValues`.

---

## 5. Notifications

```swift
// Category registered at launch
let category = UNNotificationCategory(
    identifier: "MODERATION_QUEUE",
    actions: [], intentIdentifiers: [], options: []
)
```

`ModerationPollService` (Swift `actor`), `NSBackgroundActivityScheduler` interval 120 s / tolerance 30 s.

On `newCount > lastKnownCount`:
```swift
content.title = "Moderation Queue"
content.body = "\(newCount) open report\(newCount == 1 ? "" : "s") waiting for review."
content.sound = .default
content.badge = NSNumber(value: newCount)
content.categoryIdentifier = "MODERATION_QUEUE"
```

Also posts `NotificationCenter` event `"moderationCountUpdated"` to update Dock/menu bar without waiting for next main stats fetch.

`UNUserNotificationCenterDelegate` in `AppDelegate`: allow `.banner + .sound` in foreground; navigate to Moderation on notification tap.

---

## 6. Build Phases & Effort

| Phase | Scope | Days |
|---|---|---|
| 1 | Project setup, Keychain, `AdminAPIClient`, all models, `AppState`, nav shell | 3 |
| 2 | Overview screen: stat tiles, usage bars, auto-refresh, toolbar | 2 |
| 3 | Moderation queue: list, detail, all actions, confirmation sheets, Dock/menu bar | 3 |
| 4 | Broadcast: compose form, character counters, confirmation, sent history | 1.5 |
| 5 | Recent Signups + full Settings screen | 1.5 |
| 6 | Notifications + `ModerationPollService` background scheduler | 1 |
| 7 | Polish, app icon, signing, notarisation, `.dmg` packaging | 1 |
| **Total** | | **~13 days** |

---

## 7. File / Folder Structure

```
TorqueDenAdmin.xcodeproj
TorqueDenAdmin/
├── App/
│   ├── TorqueDenAdminApp.swift          # @main, env setup
│   ├── AppDelegate.swift                # NSApplicationDelegate, UNDelegate
│   └── AppState.swift                   # ObservableObject root
│
├── Navigation/
│   ├── ContentView.swift                # NavigationSplitView root
│   ├── SidebarView.swift                # Sidebar items + badge logic
│   └── NavigationDestination.swift      # Enum: overview/moderation/broadcast/signups/settings
│
├── Screens/
│   ├── Overview/
│   │   ├── OverviewView.swift
│   │   ├── OverviewViewModel.swift
│   │   ├── StatTileView.swift
│   │   └── UsageRowView.swift
│   ├── Moderation/
│   │   ├── ModerationView.swift
│   │   ├── ModerationViewModel.swift
│   │   ├── ReportListRowView.swift
│   │   ├── ReportDetailView.swift
│   │   └── ContentTypeBadge.swift
│   ├── Broadcast/
│   │   ├── BroadcastView.swift
│   │   ├── BroadcastViewModel.swift
│   │   └── BroadcastHistoryEntry.swift
│   ├── RecentSignups/
│   │   ├── RecentSignupsView.swift
│   │   └── RecentSignupRowView.swift
│   └── Settings/
│       └── SettingsView.swift
│
├── Data/
│   ├── AdminAPIClient.swift
│   ├── Models.swift
│   ├── KeychainService.swift
│   └── ModerationPollService.swift      # NSBackgroundActivityScheduler actor
│
├── Notifications/
│   └── NotificationService.swift
│
├── MenuBar/
│   └── MenuBarController.swift
│
├── Utilities/
│   ├── DateFormatters.swift
│   ├── ByteFormatter.swift
│   └── Extensions.swift
│
├── Assets.xcassets/
│   ├── AppIcon.appiconset/
│   ├── EmberOrange.colorset/            # #FF6A2B
│   └── AppLogo.imageset/               # tyre-logo, template image for menu bar
│
└── TorqueDenAdminTests/
    ├── ModelDecodingTests.swift         # Fixture JSON → model round-trip
    ├── KeychainServiceTests.swift
    └── AdminAPIClientTests.swift        # URLProtocol stub
```

---

## 8. Key Implementation Notes

**CORS:** `URLSession` doesn't send CORS preflight requests — no changes to the Edge Function needed. The `x-admin-key` header is sent directly and works as-is.

**No key on launch:** `KeychainService.load` throws → `AppState.hasSavedKey = false` → sidebar forced to Settings, all other items show "Setup required". Restored on first successful `fetchStats()`.

**Thread safety:** All `@Published` mutations on `@MainActor`. `AdminAPIClient` methods are `async` non-isolated — ViewModels are `@MainActor` classes.

**Hardened Runtime entitlements (only these two needed):**
- `com.apple.security.network.client` — outgoing HTTPS to Supabase
- `com.apple.security.keychain-access-groups` — Keychain read/write

**Source of truth for all API shapes:**
- `supabase/functions/admin-stats/index.ts` — every field name and type in `Models.swift` must mirror this exactly
- `docs/admin/index.html` — reference for all UI states, action flows, empty states, and copy strings
