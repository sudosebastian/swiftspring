import SwiftUI
import SwiftspringKit

struct ThreadListView: View {
    @ObservedObject var environment: AppEnvironment

    private var displayedThreads: [MailThread] {
        let query = environment.mail.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return environment.mail.threads
        }
        if !environment.mail.searchResults.isEmpty {
            return environment.mail.searchResults
        }
        let lowered = query.lowercased()
        return environment.mail.threads.filter { thread in
            if thread.subject.lowercased().contains(lowered) { return true }
            if thread.snippet.lowercased().contains(lowered) { return true }
            return thread.participants.contains { person in
                person.email.lowercased().contains(lowered)
                    || (person.name?.lowercased().contains(lowered) ?? false)
            }
        }
    }

    var body: some View {
        Group {
            if displayedThreads.isEmpty {
                emptyState
            } else {
                threadList
            }
        }
        .navigationTitle(environment.mail.selectedFolder?.name ?? "Unified Inbox")
        .overlay(alignment: .top) {
            if !environment.mail.searchQuery.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("\(displayedThreads.count) result\(displayedThreads.count == 1 ? "" : "s")")
                    Spacer()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
            }
        }
    }

    private var threadList: some View {
        List(selection: Binding(
            get: { environment.mail.selectedThread?.id },
            set: { id in
                guard let id,
                      let thread = displayedThreads.first(where: { $0.id == id }) else { return }
                environment.mail.selectThread(thread)
            }
        )) {
            ForEach(displayedThreads) { thread in
                ThreadRow(thread: thread)
                    .tag(thread.id)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .contextMenu { threadContextMenu(thread) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { try? await environment.mail.trash(threadIds: [thread.id]) }
                        } label: {
                            Label("Trash", systemImage: "trash")
                        }
                        Button {
                            Task { try? await environment.mail.archive(threadIds: [thread.id]) }
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(SwiftspringBrand.spruceBright)
                    }
            }
        }
        #if os(iOS)
        .listStyle(.plain)
        #endif
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                environment.mail.searchQuery.isEmpty ? "Inbox Zero" : "No matches",
                systemImage: environment.mail.searchQuery.isEmpty ? "leaf" : "magnifyingglass"
            )
        } description: {
            Text(
                environment.mail.searchQuery.isEmpty
                    ? "Nothing here yet. Compose something, or sync an account."
                    : "Try a different search — subjects, people, and snippets are indexed."
            )
        } actions: {
            if environment.mail.searchQuery.isEmpty {
                Button("Sync") {
                    Task { await environment.syncEngine.startAll() }
                }
                .buttonStyle(.borderedProminent)
                .tint(SwiftspringBrand.spruceBright)
            }
        }
    }

    @ViewBuilder
    private func threadContextMenu(_ thread: MailThread) -> some View {
        Button(thread.unread ? "Mark Read" : "Mark Unread") {
            Task {
                try? await environment.mail.setUnread(threadIds: [thread.id], unread: !thread.unread)
            }
        }
        Button(thread.starred ? "Unstar" : "Star") {
            Task {
                try? await environment.mail.setStarred(threadIds: [thread.id], starred: !thread.starred)
            }
        }
        Button("Archive") {
            Task { try? await environment.mail.archive(threadIds: [thread.id]) }
        }
        Button("Snooze until tonight") {
            let tonight = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date())
                ?? Date().addingTimeInterval(3600)
            try? environment.snooze.snooze(threadId: thread.id, accountId: thread.accountId, until: tonight)
            environment.mail.statusMessage = "Snoozed until tonight"
        }
        Divider()
        Button("Trash", role: .destructive) {
            Task { try? await environment.mail.trash(threadIds: [thread.id]) }
        }
    }
}

struct ThreadRow: View {
    let thread: MailThread

    private var sender: String {
        thread.participants.first?.name ?? thread.participants.first?.email ?? "Unknown"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topLeading) {
                AvatarView(name: sender, size: 40)
                if thread.unread {
                    Circle()
                        .fill(SwiftspringBrand.unreadDot)
                        .frame(width: 9, height: 9)
                        .offset(x: -2, y: -2)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(sender)
                        .font(.system(size: 14, weight: thread.unread ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(SwiftspringBrand.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(thread.lastMessageReceivedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    if thread.starred {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption2)
                    }
                    Text(thread.subject.isEmpty ? "(no subject)" : thread.subject)
                        .font(.system(size: 13, weight: thread.unread ? .semibold : .regular))
                        .lineLimit(1)
                    if thread.attachmentCount > 0 || thread.messageCount > 1 {
                        Spacer(minLength: 4)
                        if thread.attachmentCount > 0 {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if thread.messageCount > 1 {
                            Text("\(thread.messageCount)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                }

                Text(thread.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct ConversationView: View {
    @ObservedObject var environment: AppEnvironment
    var onCompose: () -> Void = {}

    var body: some View {
        Group {
            if let thread = environment.mail.selectedThread {
                ZStack {
                    AtmosphereBackground()
                        .opacity(0.45)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(thread.subject.isEmpty ? "(no subject)" : thread.subject)
                                    .font(.system(size: 26, weight: .semibold, design: .serif))
                                    .foregroundStyle(SwiftspringBrand.ink)
                                HStack(spacing: 8) {
                                    if thread.starred {
                                        Label("Starred", systemImage: "star.fill")
                                            .foregroundStyle(.yellow)
                                    }
                                    Label("\(environment.mail.messages.count) messages", systemImage: "bubble.left.and.bubble.right")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .swiftspringAppear()

                            ForEach(Array(environment.mail.messages.enumerated()), id: \.element.id) { index, message in
                                MessageBubble(message: message, environment: environment)
                                    .swiftspringAppear(delay: Double(index) * 0.04)
                            }
                        }
                        .padding(.vertical)
                    }
                }
                .toolbar {
                    ToolbarItemGroup {
                        Button {
                            reply(all: false)
                        } label: {
                            Label("Reply", systemImage: "arrowshape.turn.up.left")
                        }
                        .help("Reply")

                        Button {
                            reply(all: true)
                        } label: {
                            Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
                        }

                        Button {
                            forward()
                        } label: {
                            Label("Forward", systemImage: "arrowshape.turn.up.right")
                        }

                        Button {
                            Task {
                                try? await environment.mail.setStarred(
                                    threadIds: [thread.id],
                                    starred: !thread.starred
                                )
                            }
                        } label: {
                            Label(
                                thread.starred ? "Unstar" : "Star",
                                systemImage: thread.starred ? "star.fill" : "star"
                            )
                        }

                        Button {
                            Task { try? await environment.mail.archive(threadIds: [thread.id]) }
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                    }
                }
            } else {
                ZStack {
                    AtmosphereBackground().opacity(0.5)
                    ContentUnavailableView {
                        Label("Pick a conversation", systemImage: "envelope.open")
                    } description: {
                        Text("Your reading pane is ready. Choose a thread from the list.")
                    } actions: {
                        Button("Compose") { onCompose() }
                            .buttonStyle(.borderedProminent)
                            .tint(SwiftspringBrand.spruceBright)
                    }
                }
            }
        }
        .navigationTitle("Message")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func reply(all: Bool) {
        guard let thread = environment.mail.selectedThread,
              let account = environment.accounts.accounts.first(where: { $0.id == thread.accountId }),
              let message = environment.mail.messages.last else { return }
        _ = try? environment.compose.reply(to: message, account: account, replyAll: all)
        onCompose()
    }

    private func forward() {
        guard let thread = environment.mail.selectedThread,
              let account = environment.accounts.accounts.first(where: { $0.id == thread.accountId }),
              let message = environment.mail.messages.last else { return }
        _ = try? environment.compose.forward(message: message, account: account)
        onCompose()
    }
}

struct MessageBubble: View {
    let message: Message
    @ObservedObject var environment: AppEnvironment
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                AvatarView(
                    name: message.from.first?.name ?? message.from.first?.email ?? "?",
                    size: 36
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.from.first?.displayString ?? "")
                        .font(.subheadline.weight(.semibold))
                    Text(message.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if expanded {
                Text("To: \(message.to.map(\.displayString).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let body = environment.mail.body(for: message.id)
                if let html = body?.html, !html.isEmpty {
                    HTMLMessageView(html: html)
                        .frame(minHeight: 100)
                } else if let plain = body?.plainText {
                    Text(plain)
                        .font(.body)
                        .textSelection(.enabled)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading body…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.background.opacity(0.92))
                .shadow(color: SwiftspringBrand.spruce.opacity(0.06), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SwiftspringBrand.spruce.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}
