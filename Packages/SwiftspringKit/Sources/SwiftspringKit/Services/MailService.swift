import Foundation
import Combine

@MainActor
public final class MailService: ObservableObject {
    @Published public private(set) var folders: [MailFolder] = []
    @Published public private(set) var threads: [MailThread] = []
    @Published public private(set) var selectedFolder: MailFolder?
    @Published public private(set) var selectedThread: MailThread?
    @Published public private(set) var messages: [Message] = []
    @Published public var searchQuery: String = ""
    @Published public var searchResults: [MailThread] = []
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

    public func selectThread(_ thread: MailThread) {
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
        let groups = try groupThreadIdsByAccount(threadIds)
        for (accountId, ids) in groups {
            // Optimistic local update
            for id in ids {
                if var thread = try repository.thread(id: id) {
                    thread.unread = unread
                    try repository.upsertThread(thread)
                }
            }
            let payload = ChangeUnreadPayload(threadIds: ids, unread: unread)
            let task = MailTask(
                accountId: accountId,
                kind: .changeUnread,
                payloadJSON: try MailTaskCodec.encode(payload)
            )
            try repository.enqueue(task)
            try await syncEngine.processTasks(accountId: accountId)
        }
    }

    public func setStarred(threadIds: [EntityID], starred: Bool) async throws {
        let groups = try groupThreadIdsByAccount(threadIds)
        for (accountId, ids) in groups {
            for id in ids {
                if var thread = try repository.thread(id: id) {
                    thread.starred = starred
                    try repository.upsertThread(thread)
                }
            }
            let payload = ChangeStarredPayload(threadIds: ids, starred: starred)
            let task = MailTask(
                accountId: accountId,
                kind: .changeStarred,
                payloadJSON: try MailTaskCodec.encode(payload)
            )
            try repository.enqueue(task)
            try await syncEngine.processTasks(accountId: accountId)
        }
    }

    public func move(threadIds: [EntityID], to folder: MailFolder) async throws {
        let ids = try threadIds.filter { id in
            try repository.thread(id: id)?.accountId == folder.accountId
        }
        guard !ids.isEmpty else { return }
        let payload = ChangeFolderPayload(threadIds: ids, folderId: folder.id)
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
        let groups = try groupThreadIdsByAccount(threadIds)
        for (accountId, ids) in groups {
            guard let archive = try repository.folder(accountId: accountId, role: .archive)
                ?? repository.folder(accountId: accountId, role: .all) else { continue }
            try await move(threadIds: ids, to: archive)
        }
    }

    public func trash(threadIds: [EntityID]) async throws {
        let groups = try groupThreadIdsByAccount(threadIds)
        for (accountId, ids) in groups {
            guard let trash = try repository.folder(accountId: accountId, role: .trash) else { continue }
            try await move(threadIds: ids, to: trash)
        }
    }

    private func groupThreadIdsByAccount(_ threadIds: [EntityID]) throws -> [EntityID: [EntityID]] {
        var groups: [EntityID: [EntityID]] = [:]
        for id in threadIds {
            guard let accountId = try repository.thread(id: id)?.accountId else { continue }
            groups[accountId, default: []].append(id)
        }
        return groups
    }

    public func search() {
        searchResults = (try? repository.searchThreads(query: searchQuery)) ?? []
    }

    public func body(for messageId: EntityID) -> MessageBody? {
        try? repository.body(messageId: messageId)
    }

    private func ensureBodies(for messages: [Message]) async {
        for message in messages {
            if let contacts {
                try? contacts.remember(from: message)
            }
            if !message.bodyFetched {
                try? await syncEngine.fetchBody(accountId: message.accountId, messageId: message.id)
            }
        }
    }
}
