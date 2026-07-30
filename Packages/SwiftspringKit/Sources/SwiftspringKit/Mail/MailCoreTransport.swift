import Foundation

#if canImport(MailCore)
import MailCore

/// Production transport backed by MailCore2 (`MCOIMAPSession` / `MCOSMTPSession`).
///
/// Link the MailCore XCFramework described in `Vendor/MailCore2.md`, then this type is selected
/// by `MailTransportFactory`.
public actor MailCoreTransport: MailTransport {
    private var imapSession: MCOIMAPSession?
    private var smtpSession: MCOSMTPSession?

    public init() {}

    public func connectIMAP(settings: ServerSettings, credentials: AccountCredentials) async throws {
        let session = MCOIMAPSession()
        session.hostname = settings.host
        session.port = UInt32(settings.port)
        session.username = settings.username
        apply(credentials: credentials, to: session)
        session.connectionType = connectionType(settings.security)
        imapSession = session

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = session.checkAccountOperation()
            op?.start { error in
                if let error {
                    continuation.resume(throwing: MailTransportError.authenticationFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func connectSMTP(settings: ServerSettings, credentials: AccountCredentials) async throws {
        let session = MCOSMTPSession()
        session.hostname = settings.host
        session.port = UInt32(settings.port)
        session.username = settings.username
        apply(credentials: credentials, to: session)
        session.connectionType = connectionType(settings.security)
        smtpSession = session
    }

    public func disconnect() async {
        imapSession?.disconnectOperation()?.start { _ in }
        imapSession = nil
        smtpSession = nil
    }

    public func testConnection(imap: ServerSettings, smtp: ServerSettings, credentials: AccountCredentials) async throws {
        try await connectIMAP(settings: imap, credentials: credentials)
        try await connectSMTP(settings: smtp, credentials: credentials)
    }

    public func listFolders() async throws -> [RemoteFolder] {
        guard let session = imapSession else { throw MailTransportError.notConnected }
        return try await withCheckedThrowingContinuation { continuation in
            let op = session.fetchAllFoldersOperation()
            op?.start { error, folders in
                if let error {
                    continuation.resume(throwing: MailTransportError.operationFailed(error.localizedDescription))
                    return
                }
                let mapped = (folders as? [MCOIMAPFolder] ?? []).map { folder in
                    RemoteFolder(
                        path: folder.path ?? "",
                        name: (folder.path as NSString?)?.lastPathComponent ?? folder.path ?? "",
                        delimiter: String(folder.delimiter),
                        flags: []
                    )
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    public func fetchHeaders(folderPath: String, startUID: Int64?, limit: Int) async throws -> [RemoteMessageHeader] {
        guard let session = imapSession else { throw MailTransportError.notConnected }
        let uids: MCOIndexSet
        if let startUID {
            uids = MCOIndexSet(range: MCORangeMake(UInt64(startUID), UInt64(max(limit, 1))))
        } else {
            uids = MCOIndexSet(range: MCORangeMake(1, UINT64_MAX))
        }

        return try await withCheckedThrowingContinuation { continuation in
            let kind: MCOIMAPMessagesRequestKind = [.headers, .flags, .structure]
            let op = session.fetchMessagesOperation(withFolder: folderPath, requestKind: kind, uids: uids)
            op?.start { error, messages, _ in
                if let error {
                    continuation.resume(throwing: MailTransportError.operationFailed(error.localizedDescription))
                    return
                }
                let headers = (messages as? [MCOIMAPMessage] ?? []).prefix(limit).map { message -> RemoteMessageHeader in
                    let header = message.header
                    return RemoteMessageHeader(
                        uid: Int64(message.uid),
                        headerMessageId: header?.messageID,
                        subject: header?.subject ?? "(no subject)",
                        snippet: "",
                        from: Self.mapAddresses(header?.from),
                        to: Self.mapAddresses(header?.to),
                        cc: Self.mapAddresses(header?.cc),
                        date: header?.date ?? Date(),
                        unread: !message.flags.contains(.seen),
                        starred: message.flags.contains(.flagged),
                        hasAttachments: message.attachments()?.count ?? 0 > 0,
                        references: (header?.references as? [String]) ?? []
                    )
                }
                continuation.resume(returning: Array(headers))
            }
        }
    }

    public func fetchBody(folderPath: String, uid: Int64) async throws -> RemoteMessageBody {
        guard let session = imapSession else { throw MailTransportError.notConnected }
        return try await withCheckedThrowingContinuation { continuation in
            let op = session.fetchMessageOperation(withFolder: folderPath, uid: UInt32(uid))
            op?.start { error, data in
                if let error {
                    continuation.resume(throwing: MailTransportError.operationFailed(error.localizedDescription))
                    return
                }
                guard let data,
                      let parser = MCOMessageParser(data: data) else {
                    continuation.resume(returning: RemoteMessageBody())
                    return
                }
                let html = parser.htmlRendering(with: nil)
                let plain = parser.plainTextRendering()
                let attachments = (parser.attachments() as? [MCOAttachment] ?? []).map { attachment in
                    RemoteAttachment(
                        filename: attachment.filename ?? "attachment",
                        contentType: attachment.mimeType ?? "application/octet-stream",
                        size: Int64(attachment.data?.count ?? 0),
                        contentId: attachment.contentID,
                        isInline: attachment.contentID != nil,
                        data: attachment.data
                    )
                }
                continuation.resume(returning: RemoteMessageBody(html: html, plainText: plain, attachments: attachments))
            }
        }
    }

    public func setFlags(folderPath: String, uids: [Int64], unread: Bool?, starred: Bool?) async throws {
        guard let session = imapSession else { throw MailTransportError.notConnected }
        let indexSet = MCOIndexSet()
        uids.forEach { indexSet.add(UInt64($0)) }

        if let unread {
            let flags: MCOMessageFlag = .seen
            let op = unread
                ? session.storeFlagsOperation(withFolder: folderPath, uids: indexSet, kind: .remove, flags: flags)
                : session.storeFlagsOperation(withFolder: folderPath, uids: indexSet, kind: .add, flags: flags)
            try await start(op)
        }
        if let starred {
            let flags: MCOMessageFlag = .flagged
            let op = starred
                ? session.storeFlagsOperation(withFolder: folderPath, uids: indexSet, kind: .add, flags: flags)
                : session.storeFlagsOperation(withFolder: folderPath, uids: indexSet, kind: .remove, flags: flags)
            try await start(op)
        }
    }

    public func move(folderPath: String, uids: [Int64], toFolderPath: String) async throws {
        guard let session = imapSession else { throw MailTransportError.notConnected }
        let indexSet = MCOIndexSet()
        uids.forEach { indexSet.add(UInt64($0)) }
        let op = session.copyMessagesOperation(withFolder: folderPath, uids: indexSet, destFolder: toFolderPath)
        try await start(op)
        let deleteOp = session.storeFlagsOperation(withFolder: folderPath, uids: indexSet, kind: .add, flags: .deleted)
        try await start(deleteOp)
        let expunge = session.expungeOperation(folderPath)
        try await start(expunge)
    }

    public func send(_ message: OutgoingMessage) async throws {
        guard let session = smtpSession else { throw MailTransportError.notConnected }
        let builder = MCOMessageBuilder()
        builder.header.from = MCOAddress(displayName: message.from.name, mailbox: message.from.email)
        builder.header.to = message.to.map { MCOAddress(displayName: $0.name, mailbox: $0.email) }
        builder.header.cc = message.cc.map { MCOAddress(displayName: $0.name, mailbox: $0.email) }
        builder.header.bcc = message.bcc.map { MCOAddress(displayName: $0.name, mailbox: $0.email) }
        builder.header.subject = message.subject
        if let inReplyTo = message.inReplyTo {
            builder.header.inReplyTo = [inReplyTo]
        }
        if !message.references.isEmpty {
            builder.header.references = message.references
        }
        if let html = message.htmlBody {
            builder.htmlBody = html
        } else {
            builder.textBody = message.plainTextBody ?? ""
        }
        for attachment in message.attachments {
            if let data = attachment.data {
                let mco = MCOAttachment()
                mco.filename = attachment.filename
                mco.mimeType = attachment.contentType
                mco.data = data
                builder.addAttachment(mco)
            }
        }

        guard let data = builder.data() else {
            throw MailTransportError.operationFailed("Could not build RFC822 message")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = session.sendOperation(with: data)
            op?.start { error in
                if let error {
                    continuation.resume(throwing: MailTransportError.operationFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func apply(credentials: AccountCredentials, to session: MCOIMAPSession) {
        if let token = credentials.accessToken {
            session.authType = .xoAuth2
            session.oAuth2Token = token
        } else {
            session.password = credentials.password
        }
    }

    private func apply(credentials: AccountCredentials, to session: MCOSMTPSession) {
        if let token = credentials.accessToken {
            session.authType = .xoAuth2
            session.oAuth2Token = token
        } else {
            session.password = credentials.password
        }
    }

    private func connectionType(_ security: MailSecurity) -> MCOConnectionType {
        switch security {
        case .sslTLS: return .TLS
        case .startTLS: return .startTLS
        case .none: return .clear
        }
    }

    private func start(_ operation: MCOIMAPBaseOperation?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation?.start { error in
                if let error {
                    continuation.resume(throwing: MailTransportError.operationFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func mapAddresses(_ value: Any?) -> [EmailAddress] {
        if let address = value as? MCOAddress {
            return [EmailAddress(name: address.displayName, email: address.mailbox ?? "")]
        }
        if let addresses = value as? [MCOAddress] {
            return addresses.compactMap { address in
                guard let mailbox = address.mailbox else { return nil }
                return EmailAddress(name: address.displayName, email: mailbox)
            }
        }
        return []
    }
}
#endif
