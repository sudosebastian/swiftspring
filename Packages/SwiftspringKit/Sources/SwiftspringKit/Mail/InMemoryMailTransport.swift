import Foundation

/// Development / test transport that holds mail in memory and requires no network.
public actor InMemoryMailTransport: MailTransport {
    private var connected = false
    private var folders: [RemoteFolder] = [
        RemoteFolder(path: "INBOX", name: "Inbox", flags: ["\\Inbox"]),
        RemoteFolder(path: "Sent", name: "Sent", flags: ["\\Sent"]),
        RemoteFolder(path: "Drafts", name: "Drafts", flags: ["\\Drafts"]),
        RemoteFolder(path: "Trash", name: "Trash", flags: ["\\Trash"]),
        RemoteFolder(path: "Archive", name: "Archive", flags: ["\\Archive"]),
        RemoteFolder(path: "Junk", name: "Junk", flags: ["\\Junk"]),
    ]
    private var headersByFolder: [String: [RemoteMessageHeader]] = [:]
    private var bodies: [String: RemoteMessageBody] = [:]
    private var sent: [OutgoingMessage] = []

    public init(seedDemoMail: Bool = true) {
        if seedDemoMail {
            let now = Date()
            headersByFolder["INBOX"] = [
                RemoteMessageHeader(
                    uid: 1,
                    headerMessageId: "<welcome@swiftspring.local>",
                    subject: "Welcome to Swiftspring",
                    snippet: "Your native Apple mail client is ready.",
                    from: [EmailAddress(name: "Swiftspring", email: "hello@swiftspring.app")],
                    to: [EmailAddress(email: "you@example.com")],
                    date: now.addingTimeInterval(-3600),
                    unread: true,
                    starred: true
                ),
                RemoteMessageHeader(
                    uid: 2,
                    headerMessageId: "<native@swiftspring.local>",
                    subject: "Native macOS & iOS sync",
                    snippet: "In-process IMAP with GRDB and SwiftUI.",
                    from: [EmailAddress(name: "Engineering", email: "eng@swiftspring.app")],
                    to: [EmailAddress(email: "you@example.com")],
                    date: now.addingTimeInterval(-1800),
                    unread: true
                ),
                RemoteMessageHeader(
                    uid: 3,
                    headerMessageId: "<tips@swiftspring.local>",
                    subject: "Tips for a fast inbox",
                    snippet: "Archive, star, and search without Chromium overhead.",
                    from: [EmailAddress(name: "Tips", email: "tips@swiftspring.app")],
                    to: [EmailAddress(email: "you@example.com")],
                    date: now.addingTimeInterval(-600),
                    unread: false
                ),
            ]
            bodies["INBOX:1"] = RemoteMessageBody(
                html: "<h1>Welcome</h1><p>Swiftspring runs natively on macOS and iOS.</p>",
                plainText: "Welcome\n\nSwiftspring runs natively on macOS and iOS."
            )
            bodies["INBOX:2"] = RemoteMessageBody(
                html: "<p>Sync uses MailCore2 behind a Swift actor. UI reads from GRDB.</p>",
                plainText: "Sync uses MailCore2 behind a Swift actor. UI reads from GRDB."
            )
            bodies["INBOX:3"] = RemoteMessageBody(
                html: "<p>Try starring threads and using local FTS search.</p>",
                plainText: "Try starring threads and using local FTS search."
            )
        }
    }

    public func connectIMAP(settings: ServerSettings, credentials: AccountCredentials) async throws {
        _ = settings
        guard credentials.password != nil || credentials.accessToken != nil || credentials.refreshToken != nil else {
            throw MailTransportError.authenticationFailed("Missing credentials")
        }
        connected = true
    }

    public func connectSMTP(settings: ServerSettings, credentials: AccountCredentials) async throws {
        _ = settings
        _ = credentials
        connected = true
    }

    public func disconnect() async {
        connected = false
    }

    public func testConnection(imap: ServerSettings, smtp: ServerSettings, credentials: AccountCredentials) async throws {
        try await connectIMAP(settings: imap, credentials: credentials)
        try await connectSMTP(settings: smtp, credentials: credentials)
    }

    public func listFolders() async throws -> [RemoteFolder] {
        guard connected else { throw MailTransportError.notConnected }
        return folders
    }

    public func fetchHeaders(folderPath: String, startUID: Int64?, limit: Int) async throws -> [RemoteMessageHeader] {
        guard connected else { throw MailTransportError.notConnected }
        let all = headersByFolder[folderPath] ?? []
        let filtered = all.filter { header in
            guard let startUID else { return true }
            return header.uid >= startUID
        }
        return Array(filtered.prefix(limit))
    }

    public func fetchBody(folderPath: String, uid: Int64) async throws -> RemoteMessageBody {
        guard connected else { throw MailTransportError.notConnected }
        return bodies["\(folderPath):\(uid)"] ?? RemoteMessageBody(plainText: "(empty)")
    }

    public func setFlags(folderPath: String, uids: [Int64], unread: Bool?, starred: Bool?) async throws {
        guard connected else { throw MailTransportError.notConnected }
        guard var headers = headersByFolder[folderPath] else { return }
        for index in headers.indices where uids.contains(headers[index].uid) {
            if let unread { headers[index].unread = unread }
            if let starred { headers[index].starred = starred }
        }
        headersByFolder[folderPath] = headers
    }

    public func move(folderPath: String, uids: [Int64], toFolderPath: String) async throws {
        guard connected else { throw MailTransportError.notConnected }
        let moving = (headersByFolder[folderPath] ?? []).filter { uids.contains($0.uid) }
        headersByFolder[folderPath] = (headersByFolder[folderPath] ?? []).filter { !uids.contains($0.uid) }
        headersByFolder[toFolderPath, default: []].append(contentsOf: moving)
    }

    public func send(_ message: OutgoingMessage) async throws {
        guard connected else { throw MailTransportError.notConnected }
        sent.append(message)
        let uid = Int64((headersByFolder["Sent"]?.count ?? 0) + 1)
        let header = RemoteMessageHeader(
            uid: uid,
            headerMessageId: "<sent-\(uid)@swiftspring.local>",
            subject: message.subject,
            snippet: String((message.plainTextBody ?? "").prefix(140)),
            from: [message.from],
            to: message.to,
            cc: message.cc,
            date: Date(),
            unread: false
        )
        headersByFolder["Sent", default: []].append(header)
        bodies["Sent:\(uid)"] = RemoteMessageBody(html: message.htmlBody, plainText: message.plainTextBody)
    }

    public func sentMessages() -> [OutgoingMessage] { sent }
}
