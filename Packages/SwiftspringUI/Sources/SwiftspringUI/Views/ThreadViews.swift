import SwiftUI
import SwiftspringKit

struct ThreadListView: View {
    @ObservedObject var environment: AppEnvironment

    private var displayedThreads: [Thread] {
        if !environment.mail.searchQuery.isEmpty, !environment.mail.searchResults.isEmpty {
            return environment.mail.searchResults
        }
        return environment.mail.threads
    }

    var body: some View {
        List(selection: Binding(
            get: { environment.mail.selectedThread?.id },
            set: { id in
                if let id, let thread = displayedThreads.first(where: { $0.id == id }) {
                    environment.mail.selectThread(thread)
                }
            }
        )) {
            ForEach(displayedThreads) { thread in
                ThreadRow(thread: thread)
                    .tag(thread.id)
                    .contextMenu {
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
                        Button("Trash", role: .destructive) {
                            Task { try? await environment.mail.trash(threadIds: [thread.id]) }
                        }
                        Button("Snooze until tonight") {
                            let tonight = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date().addingTimeInterval(3600)
                            try? environment.snooze.snooze(threadId: thread.id, accountId: thread.accountId, until: tonight)
                        }
                    }
            }
        }
        .navigationTitle(environment.mail.selectedFolder?.name ?? "Unified Inbox")
        #if os(iOS)
        .listStyle(.plain)
        #endif
    }
}

struct ThreadRow: View {
    let thread: Thread

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(thread.participants.first?.name ?? thread.participants.first?.email ?? "Unknown")
                    .font(thread.unread ? .headline : .body)
                    .lineLimit(1)
                Spacer()
                Text(thread.lastMessageReceivedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if thread.starred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }
                Text(thread.subject.isEmpty ? "(no subject)" : thread.subject)
                    .font(thread.unread ? .subheadline.weight(.semibold) : .subheadline)
                    .lineLimit(1)
            }
            Text(thread.snippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

struct ConversationView: View {
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        Group {
            if let thread = environment.mail.selectedThread {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        Text(thread.subject)
                            .font(.title2.weight(.semibold))
                            .padding(.horizontal)
                        ForEach(environment.mail.messages) { message in
                            MessageBubble(message: message, environment: environment)
                        }
                    }
                    .padding(.vertical)
                }
                .toolbar {
                    ToolbarItemGroup {
                        Button {
                            guard let account = environment.accounts.accounts.first(where: { $0.id == thread.accountId }),
                                  let message = environment.mail.messages.last else { return }
                            _ = try? environment.compose.reply(to: message, account: account, replyAll: false)
                        } label: {
                            Label("Reply", systemImage: "arrowshape.turn.up.left")
                        }
                        Button {
                            guard let account = environment.accounts.accounts.first(where: { $0.id == thread.accountId }),
                                  let message = environment.mail.messages.last else { return }
                            _ = try? environment.compose.reply(to: message, account: account, replyAll: true)
                        } label: {
                            Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
                        }
                        Button {
                            guard let account = environment.accounts.accounts.first(where: { $0.id == thread.accountId }),
                                  let message = environment.mail.messages.last else { return }
                            _ = try? environment.compose.forward(message: message, account: account)
                        } label: {
                            Label("Forward", systemImage: "arrowshape.turn.up.right")
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "envelope.open",
                    description: Text("Choose a thread to read.")
                )
            }
        }
        .navigationTitle("Message")
    }
}

struct MessageBubble: View {
    let message: Message
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(message.from.first?.displayString ?? "")
                    .font(.headline)
                Spacer()
                Text(message.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("To: \(message.to.map(\.displayString).joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)

            let body = environment.mail.body(for: message.id)
            if let html = body?.html, !html.isEmpty {
                HTMLMessageView(html: html)
                    .frame(minHeight: 120)
            } else if let plain = body?.plainText {
                Text(plain)
                    .textSelection(.enabled)
            } else {
                ProgressView("Loading body…")
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
