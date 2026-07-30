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
                    snippet: "Your native Apple mail client is ready — local sync, no Chromium.",
                    from: [EmailAddress(name: "Swiftspring", email: "hello@swiftspring.app")],
                    to: [EmailAddress(email: "you@example.com")],
                    date: now.addingTimeInterval(-7200),
                    unread: true,
                    starred: true
                ),
                RemoteMessageHeader(
                    uid: 2,
                    headerMessageId: "<design@swiftspring.local>",
                    subject: "A calmer reading pane",
                    snippet: "Spruce accents, serif wordmark, and HTML that respects dark mode.",
                    from: [EmailAddress(name: "Maya Chen", email: "maya@studio.example")],
                    to: [EmailAddress(email: "you@example.com")],
                    date: now.addingTimeInterval(-5400),
                    unread: true
                ),
                RemoteMessageHeader(
                    uid: 3,
                    headerMessageId: "<native@swiftspring.local>",
                    subject: "Native macOS & iOS sync",
                    snippet: "In-process IMAP with GRDB and SwiftUI — half the idle RAM of Electron.",
                    from: [EmailAddress(name: "Engineering", email: "eng@swiftspring.app")],
                    to: [EmailAddress(email: "you@example.com")],
                    date: now.addingTimeInterval(-3600),
                    unread: true
                ),
                RemoteMessageHeader(
                    uid: 4,
                    headerMessageId: "<invite@swiftspring.local>",
                    subject: "Coffee next week?",
                    snippet: "Are you free Thursday afternoon for a walk through the plan?",
                    from: [EmailAddress(name: "Jordan Lee", email: "jordan@friends.example")],
                    to: [EmailAddress(email: "you@example.com")],
                    date: now.addingTimeInterval(-1800),
                    unread: false
                ),
                RemoteMessageHeader(
                    uid: 5,
                    headerMessageId: "<tips@swiftspring.local>",
                    subject: "Tips for a fast inbox",
                    snippet: "Archive, star, snooze, and search without leaving the keyboard.",
                    from: [EmailAddress(name: "Tips", email: "tips@swiftspring.app")],
                    to: [EmailAddress(email: "you@example.com")],
                    date: now.addingTimeInterval(-600),
                    unread: false,
                    hasAttachments: true
                ),
            ]
            headersByFolder["Sent"] = [
                RemoteMessageHeader(
                    uid: 1,
                    headerMessageId: "<sent-hello@swiftspring.local>",
                    subject: "Re: Coffee next week?",
                    snippet: "Thursday works — let's meet at 3.",
                    from: [EmailAddress(email: "you@example.com")],
                    to: [EmailAddress(name: "Jordan Lee", email: "jordan@friends.example")],
                    date: now.addingTimeInterval(-900),
                    unread: false
                ),
            ]
            bodies["INBOX:1"] = RemoteMessageBody(
                html: """
                <div style="font-family:-apple-system,sans-serif;line-height:1.5;color:#141F23">
                <p style="font-size:22px;font-weight:600;margin:0 0 12px">Welcome aboard.</p>
                <p>Swiftspring is a <strong>fully native</strong> mail client for Mac and iPhone.
                Sync runs in-process. Your credentials stay in Keychain.</p>
                <p style="color:#1E7370">Try starring this thread, then search for “native”.</p>
                </div>
                """,
                plainText: "Welcome aboard.\n\nSwiftspring is a fully native mail client for Mac and iPhone."
            )
            bodies["INBOX:2"] = RemoteMessageBody(
                html: """
                <p>Hey — the reading pane now uses a sand/mist atmosphere and spruce accents so long threads feel less clinical.</p>
                <blockquote>Brand first. One job per surface. Motion with purpose.</blockquote>
                <p>— Maya</p>
                """,
                plainText: "Hey — the reading pane now uses a sand/mist atmosphere..."
            )
            bodies["INBOX:3"] = RemoteMessageBody(
                html: """
                <p>Architecture snapshot:</p>
                <ul>
                <li>SwiftUI mailbox on macOS &amp; iOS</li>
                <li>GRDB + SQLite as the UI source of truth</li>
                <li>MailCore2 behind a Swift <code>MailTransport</code></li>
                </ul>
                <p>No Electron. No JSON stdin bridge.</p>
                """,
                plainText: "Architecture snapshot: SwiftUI, GRDB, MailCore2. No Electron."
            )
            bodies["INBOX:4"] = RemoteMessageBody(
                html: "<p>Are you free Thursday afternoon for a walk through the plan? Coffee on me.</p><p>— Jordan</p>",
                plainText: "Are you free Thursday afternoon for a walk through the plan?"
            )
            bodies["INBOX:5"] = RemoteMessageBody(
                html: """
                <p><strong>Keyboard-friendly tips</strong></p>
                <ol>
                <li>⌘N — new message</li>
                <li>⌘R — sync all accounts</li>
                <li>Right-click a thread — archive, snooze, star</li>
                </ol>
                """,
                plainText: "Keyboard-friendly tips: ⌘N compose, ⌘R sync, context menu for archive/snooze."
            )
            bodies["Sent:1"] = RemoteMessageBody(
                html: "<p>Thursday works — let's meet at 3.</p>",
                plainText: "Thursday works — let's meet at 3."
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
