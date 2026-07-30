import SwiftUI
import SwiftspringKit

public struct RootMailboxView: View {
    @ObservedObject var environment: AppEnvironment
    @State private var showCompose = false
    @State private var showAccounts = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(environment: environment)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            ThreadListView(environment: environment)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            ConversationView(environment: environment)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showAccounts = true
                } label: {
                    Label("Accounts", systemImage: "person.crop.circle")
                }
                Button {
                    Task { await environment.syncEngine.startAll() }
                } label: {
                    Label("Sync", systemImage: "arrow.clockwise")
                }
                Button {
                    showCompose = true
                } label: {
                    Label("Compose", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showCompose) {
            ComposeView(environment: environment)
                #if os(macOS)
                .frame(minWidth: 640, minHeight: 480)
                #endif
        }
        .sheet(isPresented: $showAccounts) {
            AccountSetupView(environment: environment)
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 420)
                #endif
        }
        .searchable(text: $environment.mail.searchQuery, prompt: "Search mail")
        .onSubmit(of: .search) {
            environment.mail.search()
        }
        .task {
            if environment.accounts.accounts.isEmpty {
                _ = try? await environment.accounts.addDemoAccount()
            }
            environment.mail.loadFolders(accountId: environment.accounts.accounts.first?.id)
            await environment.syncEngine.startAll()
            let unread = environment.mail.threads.filter(\.unread).count
            environment.notifications.updateBadge(unreadThreads: unread)
        }
    }
}

struct SidebarView: View {
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        List(selection: Binding(
            get: { environment.mail.selectedFolder?.id },
            set: { id in
                if let id, let folder = environment.mail.folders.first(where: { $0.id == id }) {
                    environment.mail.selectFolder(folder)
                }
            }
        )) {
            Section("Inbox") {
                Button("Unified Inbox") {
                    environment.mail.selectUnifiedInbox()
                }
            }
            Section("Folders") {
                ForEach(environment.mail.folders) { folder in
                    NavigationLink(value: folder.id) {
                        Label {
                            HStack {
                                Text(folder.name)
                                Spacer()
                                if folder.unreadCount > 0 {
                                    Text("\(folder.unreadCount)")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        } icon: {
                            Image(systemName: icon(for: folder.role))
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
                    Label(account.label, systemImage: "envelope")
                        .badge(statusBadge(account.syncState))
                }
            }
        }
        .navigationTitle("Swiftspring")
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

    private func statusBadge(_ state: SyncState) -> String {
        switch state {
        case .ok: return ""
        case .syncing: return "…"
        case .authFailed: return "!"
        case .offline: return "offline"
        case .error: return "err"
        case .authenticating: return "auth"
        }
    }
}
