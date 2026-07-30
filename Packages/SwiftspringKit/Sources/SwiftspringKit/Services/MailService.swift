import Foundation
import Combine

@MainActor
public final class MailService: ObservableObject {
    @Published public private(set) var folders: [MailFolder] = []
    @Published public private(set) var threads: [Thread] = []
    @Published public private(set) var selectedFolder: MailFolder?
    @Published public private(set) var selectedThread: Thread?
    @Published public private(set) var messages: [Message] = []
    @Published public var searchQuery: String = ""
    @Published public var searchResults: [Thread] = []
    @Published public var statusMessage: String?

    public let repository: MailRepository
    public let syncEngine: SyncEngine
    public var contacts: ContactService?

    private var folderCancellable: AnyCancellable?
    private var threadCancellable: AnyCancellable?
    private var messageCancellable: AnyCancellable?

    public init(repository: MailRepository, syncEngine: SyncEngine, contacts: ContactService? = nil) {
        self.repository = repository
        self.syncEngine = syncEngine
        self.contacts = contacts
    }

    public func loadFolders(accountId: EntityID?) {
        folderCancellable = repository.observeFolders(accountId: accountId)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] folders in
                self?.folders = folders
                if self?.selectedFolder == nil {
                    self?.selectedFolder = folders.first(where: { $0.role == .inbox }) ?? folders.first
                    if let folder = self?.selectedFolder {
                        self?.selectFolder(folder)
                    }
                }
            })
    }

    public func selectFolder(_ folder: MailFolder) {
        selectedFolder = folder
        selectedThread = nil
        messages = []
        threadCancellable = repository.observeThreads(folderId: folder.id)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] threads in
                self?.threads = threads
            })
    }

    public func selectUnifiedInbox() {
        selectedFolder = nil
        threadCancellable = repository.observeThreads(folderId: nil)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] threads in
                self?.threads = threads
            })
    }

    public func selectThread(_ thread: Thread) {
        selectedThread = thread
        messageCancellable = repository.observeMessages(threadId: thread.id)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] messages in
                self?.messages = messages
                Task { await self?.ensureBodies(for: messages) }
            })

        if thread.unread {
            Task {
                try? await setUnread(threadIds: [thread.id], unread: false)
            }
        }
    }

    public func setUnread(threadIds: [EntityID], unread: Bool) async throws {
        guard let accountId = threadIds.first.flatMap({ id in try? repository.thread(id: id)?.accountId }) else { return }
        let payload = ChangeUnreadPayload(threadIds: threadIds, unread: unread)
        let task = MailTask(
            accountId: accountId,
            kind: .changeUnread,
            payloadJSON: try MailTaskCodec.encode(payload)
        )
        // Optimistic local update
        for id in threadIds {
            if var thread = try repository.thread(id: id) {
                thread.unread = unread
                try repository.upsertThread(thread)
            }
        }
        try repository.enqueue(task)
        try await syncEngine.processTasks(accountId: accountId)
    }

    public func setStarred(threadIds: [EntityID], starred: Bool) async throws {
        guard let accountId = threadIds.first.flatMap({ id in try? repository.thread(id: id)?.accountId }) else { return }
        let payload = ChangeStarredPayload(threadIds: threadIds, starred: starred)
        let task = MailTask(
            accountId: accountId,
            kind: .changeStarred,
            payloadJSON: try MailTaskCodec.encode(payload)
        )
        for id in threadIds {
            if var thread = try repository.thread(id: id) {
                thread.starred = starred
                try repository.upsertThread(thread)
            }
        }
        try repository.enqueue(task)
        try await syncEngine.processTasks(accountId: accountId)
    }

    public func move(threadIds: [EntityID], to folder: MailFolder) async throws {
        let payload = ChangeFolderPayload(threadIds: threadIds, folderId: folder.id)
        let task = MailTask(
            accountId: folder.accountId,
            kind: .changeFolder,
            payloadJSON: try MailTaskCodec.encode(payload)
        )
        try repository.enqueue(task)
        try await syncEngine.processTasks(accountId: folder.accountId)
        statusMessage = "Moved to \(folder.name)"
    }

    public func archive(threadIds: [EntityID]) async throws {
        guard let accountId = threadIds.first.flatMap({ id in try? repository.thread(id: id)?.accountId }),
              let archive = try repository.folder(accountId: accountId, role: .archive)
                ?? repository.folder(accountId: accountId, role: .all) else { return }
        try await move(threadIds: threadIds, to: archive)
    }

    public func trash(threadIds: [EntityID]) async throws {
        guard let accountId = threadIds.first.flatMap({ id in try? repository.thread(id: id)?.accountId }),
              let trash = try repository.folder(accountId: accountId, role: .trash) else { return }
        try await move(threadIds: threadIds, to: trash)
    }

    public func search() {
        searchResults = (try? repository.searchThreads(query: searchQuery)) ?? []
    }

    public func body(for messageId: EntityID) -> MessageBody? {
        try? repository.body(messageId: messageId)
    }

    private func ensureBodies(for messages: [Message]) async {
        for message in messages {
            try? contacts?.remember(from: message)
            if !message.bodyFetched {
                try? await syncEngine.fetchBody(accountId: message.accountId, messageId: message.id)
            }
        }
    }
}
