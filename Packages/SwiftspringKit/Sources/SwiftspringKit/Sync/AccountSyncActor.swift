import Foundation

public actor AccountSyncActor {
    public let accountId: EntityID
    private let repository: MailRepository
    private let credentials: CredentialStore
    private let transport: any MailTransport
    private var oauth: OAuthService
    private var oauthConfig: OAuthConfiguration?
    private var isRunning = false

    public init(
        accountId: EntityID,
        repository: MailRepository,
        credentials: CredentialStore,
        transport: any MailTransport = MailTransportFactory.make(),
        oauth: OAuthService = OAuthService(),
        oauthConfig: OAuthConfiguration? = nil
    ) {
        self.accountId = accountId
        self.repository = repository
        self.credentials = credentials
        self.transport = transport
        self.oauth = oauth
        self.oauthConfig = oauthConfig
    }

    public func start() async {
        guard !isRunning else { return }
        isRunning = true
        await setSyncState(.syncing)
        do {
            try await ensureConnected()
            try await syncFolders()
            if let inbox = try repository.folder(accountId: accountId, role: .inbox) {
                try await syncFolder(folder: inbox)
            }
            try await processPendingTasks()
            await setSyncState(.ok)
        } catch {
            await setSyncState(.error, message: error.localizedDescription)
        }
        isRunning = false
    }

    public func syncNow() async {
        await start()
    }

    public func processPendingTasks() async throws {
        let tasks = try repository.pendingTasks(accountId: accountId)
        for var task in tasks {
            do {
                try await execute(task)
                task.status = .complete
                task.updatedAt = Date()
                try repository.updateTask(task)
            } catch {
                task.status = .failed
                task.errorMessage = error.localizedDescription
                task.updatedAt = Date()
                try repository.updateTask(task)
            }
        }
    }

    private func ensureConnected() async throws {
        guard var account = try repository.account(id: accountId) else {
            throw MailTransportError.operationFailed("Account missing")
        }
        guard var creds = try credentials.load(accountId: accountId) else {
            throw MailTransportError.authenticationFailed("No credentials in Keychain")
        }

        if account.provider.usesOAuth {
            creds = try await refreshOAuthIfNeeded(account: account, credentials: creds)
        }

        do {
            try await transport.connectIMAP(settings: account.imap, credentials: creds)
            try await transport.connectSMTP(settings: account.smtp, credentials: creds)
        } catch {
            account.syncState = .authFailed
            account.syncErrorMessage = error.localizedDescription
            try repository.upsertAccount(account)
            throw error
        }
    }

    private func refreshOAuthIfNeeded(account: Account, credentials creds: AccountCredentials) async throws -> AccountCredentials {
        var updated = creds
        if let expires = updated.accessTokenExpiresAt, expires > Date().addingTimeInterval(60),
           updated.accessToken != nil {
            return updated
        }
        guard let refresh = updated.refreshToken else { return updated }
        let config = oauthConfig ?? defaultOAuthConfig(for: account.provider, clientId: updated.oauthClientId)
        guard let config else { return updated }
        let tokens = try await oauth.refreshAccessToken(refreshToken: refresh, config: config)
        updated.accessToken = tokens.accessToken
        if let refreshToken = tokens.refreshToken {
            updated.refreshToken = refreshToken
        }
        if let expiresIn = tokens.expiresIn {
            updated.accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        }
        try credentials.save(accountId: accountId, credentials: updated)
        return updated
    }

    private func defaultOAuthConfig(for provider: MailProvider, clientId: String?) -> OAuthConfiguration? {
        guard let clientId, !clientId.isEmpty else { return nil }
        switch provider {
        case .gmail: return .google(clientId: clientId)
        case .office365, .outlook: return .microsoft(clientId: clientId)
        default: return nil
        }
    }

    public func syncFolders() async throws {
        let remote = try await transport.listFolders()
        let folders = remote.map { remoteFolder in
            MailFolder(
                accountId: accountId,
                path: remoteFolder.path,
                name: remoteFolder.name,
                role: ProviderPresets.mapRole(path: remoteFolder.path, flags: remoteFolder.flags),
                delimiter: remoteFolder.delimiter
            )
        }
        // Preserve existing IDs when path matches.
        let existing = try repository.folders(accountId: accountId)
        let byPath = Dictionary(uniqueKeysWithValues: existing.map { ($0.path, $0) })
        let merged = folders.map { folder -> MailFolder in
            var copy = folder
            if let prior = byPath[folder.path] {
                copy.id = prior.id
                copy.uidValidity = prior.uidValidity
                copy.uidNext = prior.uidNext
                copy.highestModSeq = prior.highestModSeq
            }
            return copy
        }
        try repository.upsertFolders(merged)
    }

    public func syncFolder(folder: MailFolder) async throws {
        let headers = try await transport.fetchHeaders(folderPath: folder.path, startUID: folder.uidNext, limit: 200)
        guard !headers.isEmpty else { return }

        var threadMap: [String: MailThread] = [:]
        var messages: [Message] = []

        // Load existing threads keyed by first message-id when possible is expensive;
        // for MVP we create/update based on ThreadingEngine keys within this batch + DB subject match.
        for header in headers {
            let key = ThreadingEngine.threadKey(for: header)
            var thread = threadMap[key] ?? MailThread(
                accountId: accountId,
                subject: ThreadingEngine.normalizedSubject(header.subject).isEmpty
                    ? header.subject
                    : header.subject,
                folderIds: [folder.id]
            )
            if threadMap[key] == nil {
                // Try find existing by subject + participants later; new id for now.
                thread.subject = header.subject
                thread.firstMessageAt = header.date
            }
            thread.snippet = header.snippet.isEmpty ? thread.snippet : header.snippet
            thread.unread = thread.unread || header.unread
            thread.starred = thread.starred || header.starred
            thread.participants = uniqueAddresses(thread.participants + header.from + header.to)
            thread.lastMessageReceivedAt = max(thread.lastMessageReceivedAt, header.date)
            thread.messageCount += 1
            if header.hasAttachments { thread.attachmentCount += 1 }
            if !thread.folderIds.contains(folder.id) {
                thread.folderIds.append(folder.id)
            }
            threadMap[key] = thread

            let message = Message(
                accountId: accountId,
                threadId: thread.id,
                folderId: folder.id,
                imapUID: header.uid,
                headerMessageId: header.headerMessageId,
                subject: header.subject,
                snippet: header.snippet,
                from: header.from,
                to: header.to,
                cc: header.cc,
                date: header.date,
                unread: header.unread,
                starred: header.starred,
                hasAttachments: header.hasAttachments
            )
            messages.append(message)
        }

        try repository.upsertThreads(Array(threadMap.values))
        try repository.upsertMessages(messages)

        var updatedFolder = folder
        if let maxUID = headers.map(\.uid).max() {
            updatedFolder.uidNext = maxUID + 1
        }
        updatedFolder.totalCount = max(updatedFolder.totalCount, messages.count)
        updatedFolder.unreadCount = messages.filter(\.unread).count
        try repository.upsertFolder(updatedFolder)
    }

    private func execute(_ task: MailTask) async throws {
        switch task.kind {
        case .changeUnread:
            let payload = try MailTaskCodec.decode(ChangeUnreadPayload.self, from: task.payloadJSON)
            try await applyUnread(payload)
        case .changeStarred:
            let payload = try MailTaskCodec.decode(ChangeStarredPayload.self, from: task.payloadJSON)
            try await applyStarred(payload)
        case .changeFolder:
            let payload = try MailTaskCodec.decode(ChangeFolderPayload.self, from: task.payloadJSON)
            try await applyMove(payload)
        case .fetchBody:
            let payload = try MailTaskCodec.decode(FetchBodyPayload.self, from: task.payloadJSON)
            try await fetchAndStoreBody(messageId: payload.messageId)
        case .sendDraft:
            let payload = try MailTaskCodec.decode(SendDraftPayload.self, from: task.payloadJSON)
            try await sendDraft(messageId: payload.messageId, undoDelay: payload.undoDelaySeconds)
        case .syncbackDraft, .destroyDraft, .changeLabels, .syncFolder:
            // Handled by dedicated services / later phases; acknowledge for now.
            break
        }
    }

    private func applyUnread(_ payload: ChangeUnreadPayload) async throws {
        for threadId in payload.threadIds {
            guard var thread = try repository.thread(id: threadId) else { continue }
            thread.unread = payload.unread
            try repository.upsertThread(thread)
            var messages = try repository.messages(threadId: threadId)
            let uids = messages.compactMap(\.imapUID)
            if let folderId = messages.first?.folderId,
               let folder = try repository.folder(id: folderId),
               !uids.isEmpty {
                try await transport.setFlags(folderPath: folder.path, uids: uids, unread: payload.unread, starred: nil)
            }
            for index in messages.indices {
                messages[index].unread = payload.unread
                try repository.upsertMessage(messages[index])
            }
        }
        for messageId in payload.messageIds {
            guard var message = try repository.message(id: messageId) else { continue }
            message.unread = payload.unread
            try repository.upsertMessage(message)
            if let uid = message.imapUID, let folderId = message.folderId,
               let folder = try repository.folder(id: folderId) {
                try await transport.setFlags(folderPath: folder.path, uids: [uid], unread: payload.unread, starred: nil)
            }
        }
    }

    private func applyStarred(_ payload: ChangeStarredPayload) async throws {
        for threadId in payload.threadIds {
            guard var thread = try repository.thread(id: threadId) else { continue }
            thread.starred = payload.starred
            try repository.upsertThread(thread)
            var messages = try repository.messages(threadId: threadId)
            let uids = messages.compactMap(\.imapUID)
            if let folderId = messages.first?.folderId,
               let folder = try repository.folder(id: folderId),
               !uids.isEmpty {
                try await transport.setFlags(folderPath: folder.path, uids: uids, unread: nil, starred: payload.starred)
            }
            for index in messages.indices {
                messages[index].starred = payload.starred
                try repository.upsertMessage(messages[index])
            }
        }
    }

    private func applyMove(_ payload: ChangeFolderPayload) async throws {
        guard let destination = try repository.folder(id: payload.folderId) else { return }
        for threadId in payload.threadIds {
            let messages = try repository.messages(threadId: threadId)
            guard let sourceFolderId = messages.first?.folderId,
                  let source = try repository.folder(id: sourceFolderId) else { continue }
            let uids = messages.compactMap(\.imapUID)
            if !uids.isEmpty {
                try await transport.move(folderPath: source.path, uids: uids, toFolderPath: destination.path)
            }
            if var thread = try repository.thread(id: threadId) {
                thread.folderIds = [destination.id]
                try repository.upsertThread(thread)
            }
            for var message in messages {
                message.folderId = destination.id
                try repository.upsertMessage(message)
            }
        }
    }

    public func fetchAndStoreBody(messageId: EntityID) async throws {
        guard var message = try repository.message(id: messageId),
              let uid = message.imapUID,
              let folderId = message.folderId,
              let folder = try repository.folder(id: folderId) else { return }
        let remote = try await transport.fetchBody(folderPath: folder.path, uid: uid)
        let body = MessageBody(messageId: messageId, html: remote.html, plainText: remote.plainText)
        try repository.saveBody(body)
        for attachment in remote.attachments {
            var file = AttachmentFile(
                messageId: messageId,
                accountId: accountId,
                filename: attachment.filename,
                contentType: attachment.contentType,
                size: attachment.size,
                contentId: attachment.contentId,
                isInline: attachment.isInline
            )
            if let data = attachment.data {
                let url = repository.db.attachmentsDirectory
                    .appendingPathComponent(file.id.rawValue)
                    .appendingPathExtension((attachment.filename as NSString).pathExtension)
                try data.write(to: url)
                file.localPath = url.path
            }
            try repository.upsertAttachment(file)
        }
        message.bodyFetched = true
        message.hasAttachments = !remote.attachments.isEmpty || message.hasAttachments
        try repository.upsertMessage(message)
    }

    private func sendDraft(messageId: EntityID, undoDelay: Int) async throws {
        if undoDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(undoDelay) * 1_000_000_000)
        }
        guard let message = try repository.message(id: messageId),
              let account = try repository.account(id: accountId) else { return }
        let body = try repository.body(messageId: messageId)
        let attachments = try repository.attachments(messageId: messageId)
        let outgoing = OutgoingMessage(
            from: message.from.first ?? EmailAddress(name: account.name, email: account.emailAddress),
            to: message.to,
            cc: message.cc,
            bcc: message.bcc,
            subject: message.subject,
            htmlBody: body?.html,
            plainTextBody: body?.plainText,
            attachments: attachments.map {
                var data: Data?
                if let path = $0.localPath {
                    data = try? Data(contentsOf: URL(fileURLWithPath: path))
                }
                return RemoteAttachment(
                    filename: $0.filename,
                    contentType: $0.contentType,
                    size: $0.size,
                    contentId: $0.contentId,
                    isInline: $0.isInline,
                    data: data
                )
            },
            inReplyTo: message.replyToHeaderMessageId,
            references: message.replyToHeaderMessageId.map { [$0] } ?? []
        )
        try await transport.send(outgoing)
        var sent = message
        sent.draft = false
        sent.pristine = true
        try repository.upsertMessage(sent)
    }

    private func setSyncState(_ state: SyncState, message: String? = nil) async {
        guard var account = try? repository.account(id: accountId) else { return }
        account.syncState = state
        account.syncErrorMessage = message
        account.updatedAt = Date()
        try? repository.upsertAccount(account)
    }

    private func uniqueAddresses(_ addresses: [EmailAddress]) -> [EmailAddress] {
        var seen = Set<String>()
        var result: [EmailAddress] = []
        for address in addresses {
            if seen.insert(address.email).inserted {
                result.append(address)
            }
        }
        return result
    }
}
