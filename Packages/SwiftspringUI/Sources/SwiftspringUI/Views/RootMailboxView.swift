import SwiftUI
import SwiftspringKit

public struct RootMailboxView: View {
    @ObservedObject var environment: AppEnvironment
    @State private var showCompose = false
    @State private var showAccounts = false
    @State private var isSyncing = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @AppStorage("swiftspring.hasLaunched") private var hasLaunched = false

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        Group {
            if !hasLaunched {
                WelcomeView(environment: environment) {
                    hasLaunched = true
                    showAccounts = environment.accounts.accounts.isEmpty
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                mailbox
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: hasLaunched)
    }

    private var mailbox: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(environment: environment)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            } content: {
                ThreadListView(environment: environment)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 360)
            } detail: {
                ConversationView(environment: environment, onCompose: { showCompose = true })
            }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        showAccounts = true
                    } label: {
                        Label("Accounts", systemImage: "person.crop.circle")
                    }
                    .help("Manage accounts")

                    Button {
                        Task { await syncAll() }
                    } label: {
                        Label("Sync", systemImage: "arrow.clockwise")
                    }
                    .help("Sync all accounts")
                    .disabled(isSyncing)

                    Button {
                        showCompose = true
                    } label: {
                        Label("Compose", systemImage: "square.and.pencil")
                    }
                    .help("New message ⌘N")
                    .keyboardShortcut("n", modifiers: [.command])
                }
            }
            .searchable(text: $environment.mail.searchQuery, prompt: "Search mail")
            .onSubmit(of: .search) {
                environment.mail.search()
            }
            .tint(SwiftspringBrand.spruceBright)

            SyncStatusBar(
                accounts: environment.accounts.accounts,
                isSyncing: isSyncing,
                message: environment.mail.statusMessage ?? environment.notifications.status
            )
        }
        .sheet(isPresented: $showCompose) {
            ComposeView(environment: environment)
                #if os(macOS)
                .frame(minWidth: 680, minHeight: 520)
                #endif
        }
        .sheet(isPresented: $showAccounts) {
            AccountSetupView(environment: environment)
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 460)
                #endif
        }
        .task {
            if environment.accounts.accounts.isEmpty {
                // Welcome already handled demo; if user skipped, keep empty until add account.
            } else {
                environment.mail.loadFolders(accountId: nil)
                await syncAll()
            }
        }
        .onChange(of: environment.accounts.accounts.count) { _, count in
            if count > 0 {
                environment.mail.loadFolders(accountId: nil)
            }
        }
    }

    @MainActor
    private func syncAll() async {
        isSyncing = true
        defer { isSyncing = false }
        await environment.syncEngine.startAll()
        environment.accounts.refresh()
        if environment.mail.selectedFolder == nil {
            environment.mail.selectUnifiedInbox()
        }
        let unread = environment.mail.threads.filter(\.unread).count
        environment.notifications.updateBadge(unreadThreads: unread)
        environment.notifications.status = "Synced \(environment.accounts.accounts.count) account(s)"
    }
}

struct SidebarView: View {
    @ObservedObject var environment: AppEnvironment

    private var primaryFolders: [MailFolder] {
        let preferred: [FolderRole] = [.inbox, .starred, .drafts, .sent, .archive, .trash, .spam]
        return environment.mail.folders
            .filter { preferred.contains($0.role) || $0.role == .none }
            .sorted { lhs, rhs in
                let order: [FolderRole: Int] = [
                    .inbox: 0, .starred: 1, .drafts: 2, .sent: 3, .archive: 4, .all: 5, .trash: 6, .spam: 7, .important: 8, .none: 9,
                ]
                return (order[lhs.role] ?? 99) < (order[rhs.role] ?? 99)
            }
    }

    var body: some View {
        List(selection: Binding(
            get: { environment.mail.selectedFolder?.id },
            set: { id in
                if let id, let folder = environment.mail.folders.first(where: { $0.id == id }) {
                    environment.mail.selectFolder(folder)
                }
            }
        )) {
            Section {
                SwiftspringWordmark(size: 22)
                    .padding(.vertical, 4)
                    .listRowSeparator(.hidden)
            }

            Section("Mailbox") {
                Button {
                    environment.mail.selectUnifiedInbox()
                } label: {
                    Label("Unified Inbox", systemImage: "tray.2")
                }
                .listRowBackground(
                    environment.mail.selectedFolder == nil
                        ? SwiftspringBrand.spruceBright.opacity(0.12)
                        : Color.clear
                )

                ForEach(primaryFolders) { folder in
                    NavigationLink(value: folder.id) {
                        Label {
                            HStack {
                                Text(folder.name)
                                Spacer()
                                if folder.unreadCount > 0 {
                                    Text("\(folder.unreadCount)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(SwiftspringBrand.spruceBright, in: Capsule())
                                }
                            }
                        } icon: {
                            Image(systemName: icon(for: folder.role))
                                .foregroundStyle(SwiftspringBrand.spruceBright)
                        }
                    }
                    .tag(folder.id)
                }
            }

            Section("More") {
                NavigationLink {
                    ContactsView(environment: environment)
                } label: {
                    Label("Contacts", systemImage: "person.2")
                }
                NavigationLink {
                    CalendarListView(environment: environment)
                } label: {
                    Label("Calendar", systemImage: "calendar")
                }
            }

            Section("Accounts") {
                ForEach(environment.accounts.accounts) { account in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: account.colorHex) ?? SwiftspringBrand.spruceBright)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .font(.subheadline.weight(.medium))
                            Text(account.emailAddress)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        syncGlyph(account.syncState)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("")
    }

    private func icon(for role: FolderRole) -> String {
        switch role {
        case .inbox: return "tray"
        case .sent: return "paperplane"
        case .drafts: return "doc"
        case .trash: return "trash"
        case .spam: return "xmark.bin"
        case .archive, .all: return "archivebox"
        case .starred: return "star"
        case .important: return "exclamationmark.circle"
        case .none: return "folder"
        }
    }

    @ViewBuilder
    private func syncGlyph(_ state: SyncState) -> some View {
        switch state {
        case .ok:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SwiftspringBrand.spruceBright)
                .font(.caption)
        case .syncing, .authenticating:
            ProgressView().controlSize(.mini)
        case .authFailed, .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(SwiftspringBrand.coral)
                .font(.caption)
        case .offline:
            Image(systemName: "wifi.slash")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}

extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
